#import "LQFaceCaptureViewController.h"
#import <AVFoundation/AVFoundation.h>

static const CGFloat LQFaceFrameWidthFraction = 0.75;

@interface LQFaceCaptureViewController () <AVCapturePhotoCaptureDelegate>
@property (nonatomic, copy) LQFaceCaptureCompletion completion;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCapturePhotoOutput *photoOutput;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) UIView *previewView;
@property (nonatomic) NSArray<UIView *> *dimViews;
@property (nonatomic) UIImageView *guideImageView;
@property (nonatomic) UIView *guideBorderView;
@property (nonatomic) UIButton *backButton;
@property (nonatomic) UIButton *shutterButton;
@property (nonatomic) CGRect guideRect;
@property (nonatomic) CGSize capturedPreviewSize;
@property (nonatomic) CGRect capturedGuideRect;
@property (nonatomic) BOOL configured;
@property (nonatomic) BOOL capturing;
@property (nonatomic) BOOL resolved;
@end

@implementation LQFaceCaptureViewController

- (instancetype)initWithCompletion:(LQFaceCaptureCompletion)completion {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _completion = [completion copy];
        _sessionQueue = dispatch_queue_create("io.github.unifacecapture.session", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    [self buildCaptureView];
    [self authorizeCamera];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startSessionIfConfigured];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopSession];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewView.frame = self.view.bounds;
    self.previewLayer.frame = self.previewView.bounds;
    [self updatePreviewOrientation];

    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    CGFloat side = width * LQFaceFrameWidthFraction;
    self.guideRect = CGRectMake((width - side) / 2.0, (height - side) / 2.0, side, side);
    CGFloat minX = CGRectGetMinX(self.guideRect);
    CGFloat maxX = CGRectGetMaxX(self.guideRect);
    CGFloat minY = CGRectGetMinY(self.guideRect);
    CGFloat maxY = CGRectGetMaxY(self.guideRect);

    self.dimViews[0].frame = CGRectMake(0, 0, width, minY);
    self.dimViews[1].frame = CGRectMake(0, maxY, width, MAX(0, height - maxY));
    self.dimViews[2].frame = CGRectMake(0, minY, minX, side);
    self.dimViews[3].frame = CGRectMake(maxX, minY, MAX(0, width - maxX), side);
    self.guideImageView.frame = self.guideRect;
    self.guideBorderView.frame = self.guideRect;

    CGFloat safeTop = self.view.safeAreaInsets.top;
    self.backButton.frame = CGRectMake(12, safeTop + 4.0, 52, 52);
    CGFloat shutterSide = 76.0;
    CGFloat desiredCenterY = maxY + 32.0 + shutterSide / 2.0;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat maximumCenterY = height - safeBottom - shutterSide / 2.0 - 12.0;
    self.shutterButton.bounds = CGRectMake(0, 0, shutterSide, shutterSide);
    self.shutterButton.center = CGPointMake(width / 2.0, MIN(desiredCenterY, maximumCenterY));
    self.shutterButton.layer.cornerRadius = shutterSide / 2.0;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (void)buildCaptureView {
    self.previewView = [[UIView alloc] initWithFrame:CGRectZero];
    self.previewView.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.previewView];

    self.previewLayer = [AVCaptureVideoPreviewLayer layer];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.previewView.layer addSublayer:self.previewLayer];

    NSMutableArray<UIView *> *dimViews = [NSMutableArray arrayWithCapacity:4];
    for (NSInteger index = 0; index < 4; index += 1) {
        UIView *dim = [[UIView alloc] initWithFrame:CGRectZero];
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.60];
        [self.view addSubview:dim];
        [dimViews addObject:dim];
    }
    self.dimViews = dimViews;

    self.guideImageView = [[UIImageView alloc] initWithImage:[self loadGuideImage]];
    self.guideImageView.contentMode = UIViewContentModeScaleToFill;
    self.guideImageView.userInteractionEnabled = NO;
    [self.view addSubview:self.guideImageView];

    self.guideBorderView = [[UIView alloc] initWithFrame:CGRectZero];
    self.guideBorderView.userInteractionEnabled = NO;
    self.guideBorderView.backgroundColor = UIColor.clearColor;
    self.guideBorderView.layer.borderColor = UIColor.whiteColor.CGColor;
    self.guideBorderView.layer.borderWidth = 2.0;
    [self.view addSubview:self.guideBorderView];

    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setTitle:@"‹" forState:UIControlStateNormal];
    [self.backButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.backButton.titleLabel.font = [UIFont systemFontOfSize:42 weight:UIFontWeightRegular];
    [self.backButton addTarget:self action:@selector(cancelCapture) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backButton];

    self.shutterButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.shutterButton.backgroundColor = UIColor.whiteColor;
    self.shutterButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    self.shutterButton.layer.borderWidth = 8.0;
    self.shutterButton.enabled = NO;
    [self.shutterButton addTarget:self action:@selector(takePhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shutterButton];

    if (self.guideImageView.image == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithErrorCode:@"GUIDE_IMAGE_MISSING" message:@"人脸引导图资源缺失"];
        });
    }
}

- (UIImage *)loadGuideImage {
    NSArray<NSBundle *> *bundles = @[[NSBundle bundleForClass:self.class], NSBundle.mainBundle];
    for (NSBundle *bundle in bundles) {
        NSString *path = [bundle pathForResource:@"face_guide_overlay" ofType:@"png"];
        UIImage *image = path.length > 0 ? [UIImage imageWithContentsOfFile:path] : nil;
        if (image != nil) {
            return image;
        }
    }
    return [UIImage imageNamed:@"face_guide_overlay"];
}

- (void)authorizeCamera {
    NSString *usage = [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSCameraUsageDescription"];
    if (usage.length == 0) {
        [self finishWithErrorCode:@"CAMERA_USAGE_MISSING" message:@"宿主未配置相机用途说明"];
        return;
    }
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        [self configureSession];
        return;
    }
    if (status == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [self configureSession];
                } else {
                    [self finishWithErrorCode:@"CAMERA_PERMISSION_DENIED" message:@"未获得相机权限"];
                }
            });
        }];
        return;
    }
    [self finishWithErrorCode:@"CAMERA_PERMISSION_DENIED" message:@"未获得相机权限"];
}

- (void)configureSession {
    if (self.configured || self.resolved) {
        return;
    }
    self.configured = YES;
    dispatch_async(self.sessionQueue, ^{
        AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
            mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionFront];
        if (camera == nil) {
            [self finishWithErrorCode:@"FRONT_CAMERA_UNAVAILABLE" message:@"设备没有可用的前置相机"];
            return;
        }

        NSError *inputError = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&inputError];
        if (input == nil) {
            [self finishWithErrorCode:@"CAMERA_INPUT_FAILED" message:@"无法连接前置相机"];
            return;
        }

        AVCaptureSession *session = [[AVCaptureSession alloc] init];
        session.sessionPreset = AVCaptureSessionPresetPhoto;
        AVCapturePhotoOutput *output = [[AVCapturePhotoOutput alloc] init];
        [session beginConfiguration];
        if (![session canAddInput:input] || ![session canAddOutput:output]) {
            [session commitConfiguration];
            [self finishWithErrorCode:@"CAMERA_CONFIGURATION_FAILED" message:@"相机配置失败"];
            return;
        }
        [session addInput:input];
        [session addOutput:output];
        [session commitConfiguration];
        self.session = session;
        self.photoOutput = output;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.previewLayer.session = session;
            [self updatePreviewOrientation];
        });
        [session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.shutterButton.enabled = session.isRunning && !self.resolved;
            self.shutterButton.alpha = self.shutterButton.enabled ? 1.0 : 0.5;
        });
    });
}

- (void)startSessionIfConfigured {
    AVCaptureSession *session = self.session;
    if (session == nil || session.isRunning || self.resolved) {
        return;
    }
    dispatch_async(self.sessionQueue, ^{
        [session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.shutterButton.enabled = session.isRunning;
            self.shutterButton.alpha = session.isRunning ? 1.0 : 0.5;
        });
    });
}

- (void)stopSession {
    AVCaptureSession *session = self.session;
    if (session == nil || !session.isRunning) {
        return;
    }
    dispatch_async(self.sessionQueue, ^{
        [session stopRunning];
    });
}

- (void)updatePreviewOrientation {
    AVCaptureConnection *connection = self.previewLayer.connection;
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    if (connection.isVideoMirroringSupported) {
        connection.automaticallyAdjustsVideoMirroring = NO;
        connection.videoMirrored = YES;
    }
}

- (void)takePhoto {
    if (self.capturing || !self.session.isRunning || self.photoOutput == nil) {
        return;
    }
    self.capturing = YES;
    self.capturedGuideRect = self.guideRect;
    self.capturedPreviewSize = self.view.bounds.size;
    self.shutterButton.enabled = NO;
    self.shutterButton.alpha = 0.5;
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettings];
    AVCaptureConnection *connection = [self.photoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoOrientationSupported) {
        connection.videoOrientation = AVCaptureVideoOrientationPortrait;
    }
    if (connection.isVideoMirroringSupported) {
        connection.automaticallyAdjustsVideoMirroring = NO;
        connection.videoMirrored = NO;
    }
    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
    error:(NSError *)error {
    (void)output;
    if (error != nil) {
        [self recoverFromCaptureFailure:@"拍照失败，请重试"];
        return;
    }
    NSData *data = [photo fileDataRepresentation];
    UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
    UIImage *normalized = [self normalizedImage:image];
    UIImage *cropped = [self cropImage:normalized
        toGuideRect:self.capturedGuideRect
        previewSize:self.capturedPreviewSize];
    if (cropped == nil) {
        [self recoverFromCaptureFailure:@"图片处理失败，请重试"];
        return;
    }

    NSData *jpeg = UIImageJPEGRepresentation(cropped, 0.92);
    NSString *fileName = [NSString stringWithFormat:@"face_capture_%@.jpg", NSUUID.UUID.UUIDString];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSError *writeError = nil;
    if (jpeg.length == 0 || ![jpeg writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
        [self recoverFromCaptureFailure:@"图片保存失败，请重试"];
        return;
    }

    NSDictionary *result = @{
        @"code": @0,
        @"path": path,
        @"uri": [NSURL fileURLWithPath:path].absoluteString,
        @"width": @(CGImageGetWidth(cropped.CGImage)),
        @"height": @(CGImageGetHeight(cropped.CGImage))
    };
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finishWithResult:result];
    });
}

- (UIImage *)normalizedImage:(UIImage *)image {
    if (image == nil) {
        return nil;
    }
    if (image.imageOrientation == UIImageOrientationUp) {
        return image;
    }
    UIGraphicsBeginImageContextWithOptions(image.size, YES, 1.0);
    [image drawInRect:(CGRect){CGPointZero, image.size}];
    UIImage *normalized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return normalized;
}

/** Maps the centered aspect-fill preview and guide rectangle into normalized photo pixels. */
- (UIImage *)cropImage:(UIImage *)image
    toGuideRect:(CGRect)guideRect
    previewSize:(CGSize)previewSize {
    if (image.CGImage == nil || CGRectIsEmpty(guideRect)
        || previewSize.width <= 0 || previewSize.height <= 0) {
        return nil;
    }
    CGFloat sourceWidth = CGImageGetWidth(image.CGImage);
    CGFloat sourceHeight = CGImageGetHeight(image.CGImage);
    CGFloat previewWidth = previewSize.width;
    CGFloat previewHeight = previewSize.height;
    CGFloat sourceRatio = sourceWidth / sourceHeight;
    CGFloat previewRatio = previewWidth / previewHeight;
    CGFloat visibleLeft = 0;
    CGFloat visibleTop = 0;
    CGFloat visibleWidth = sourceWidth;
    CGFloat visibleHeight = sourceHeight;
    if (sourceRatio > previewRatio) {
        visibleWidth = sourceHeight * previewRatio;
        visibleLeft = (sourceWidth - visibleWidth) / 2.0;
    } else if (sourceRatio < previewRatio) {
        visibleHeight = sourceWidth / previewRatio;
        visibleTop = (sourceHeight - visibleHeight) / 2.0;
    }

    CGFloat left = visibleLeft + CGRectGetMinX(guideRect) / previewWidth * visibleWidth;
    CGFloat top = visibleTop + CGRectGetMinY(guideRect) / previewHeight * visibleHeight;
    CGFloat width = CGRectGetWidth(guideRect) / previewWidth * visibleWidth;
    CGFloat height = CGRectGetHeight(guideRect) / previewHeight * visibleHeight;
    CGFloat side = MIN(width, height);
    CGRect crop = CGRectIntegral(CGRectMake(
        left + (width - side) / 2.0,
        top + (height - side) / 2.0,
        side,
        side
    ));
    crop = CGRectIntersection(crop, CGRectMake(0, 0, sourceWidth, sourceHeight));
    CGFloat finalSide = MIN(CGRectGetWidth(crop), CGRectGetHeight(crop));
    if (finalSide < 1) {
        return nil;
    }
    crop.size = CGSizeMake(finalSide, finalSide);
    CGImageRef croppedRef = CGImageCreateWithImageInRect(image.CGImage, crop);
    if (croppedRef == nil) {
        return nil;
    }
    UIImage *cropped = [UIImage imageWithCGImage:croppedRef scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(croppedRef);
    return cropped;
}

- (void)recoverFromCaptureFailure:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.capturing = NO;
        self.shutterButton.enabled = self.session.isRunning;
        self.shutterButton.alpha = self.shutterButton.enabled ? 1.0 : 0.5;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)cancelCapture {
    [self finishWithResult:@{
        @"code": @1,
        @"errorCode": @"CANCELLED",
        @"message": @"已取消人脸拍照"
    }];
}

- (void)finishWithErrorCode:(NSString *)errorCode message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self finishWithResult:@{
            @"code": @-1,
            @"errorCode": errorCode ?: @"UNKNOWN",
            @"message": message ?: @"人脸拍照失败"
        }];
    });
}

- (void)finishWithResult:(NSDictionary *)result {
    if (self.resolved) {
        return;
    }
    self.resolved = YES;
    self.capturing = NO;
    LQFaceCaptureCompletion callback = self.completion;
    self.completion = nil;
    [self stopSession];
    [self dismissViewControllerAnimated:YES completion:^{
        if (callback != nil) {
            callback(result);
        }
    }];
}

@end
