#import "LQFaceCaptureViewController.h"
#import "LQFaceCaptureResourceData.h"
#import <AVFoundation/AVFoundation.h>

static const CGFloat LQFaceFrameWidthFraction = 0.90;

@interface LQFaceCaptureViewController () <AVCapturePhotoCaptureDelegate>
@property (nonatomic, copy) LQFaceCaptureCompletion completion;
@property (nonatomic) AVCaptureSession *session;
@property (nonatomic) AVCaptureDeviceInput *videoInput;
@property (nonatomic) AVCapturePhotoOutput *photoOutput;
@property (nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) UIView *previewView;
@property (nonatomic) NSArray<UIView *> *dimViews;
@property (nonatomic) UIImageView *guideImageView;
@property (nonatomic) UIView *guideBorderView;
@property (nonatomic) UIButton *backButton;
@property (nonatomic) UIButton *shutterButton;
@property (nonatomic) UIButton *switchButton;
@property (nonatomic) UILabel *zoomHintLabel;
@property (nonatomic) AVCaptureDevicePosition cameraPosition;
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
        _cameraPosition = AVCaptureDevicePositionBack;
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
    CGFloat guideCenterY = height / 2.0 - side / 3.0;
    CGFloat guideTop = MAX(0, guideCenterY - side / 2.0);
    self.guideRect = CGRectMake((width - side) / 2.0, guideTop, side, side);
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
    self.zoomHintLabel.frame = CGRectMake(20, maxY + 14.0, width - 40.0, 24.0);
    CGFloat shutterSide = 76.0;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat bottomClearance = MAX(safeBottom + 12.0, height / 8.0);
    self.shutterButton.bounds = CGRectMake(0, 0, shutterSide, shutterSide);
    self.shutterButton.center = CGPointMake(width / 2.0,
        height - bottomClearance - shutterSide / 2.0);
    self.shutterButton.layer.cornerRadius = shutterSide / 2.0;
    CGFloat switchSide = 52.0;
    CGFloat desiredSwitchCenterX = CGRectGetMidX(self.shutterButton.frame) + 90.0;
    self.switchButton.bounds = CGRectMake(0, 0, switchSide, switchSide);
    self.switchButton.center = CGPointMake(MIN(width - 20.0 - switchSide / 2.0, desiredSwitchCenterX),
        CGRectGetMidY(self.shutterButton.frame));
    self.switchButton.layer.cornerRadius = switchSide / 2.0;
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
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self
        action:@selector(handlePinch:)];
    [self.previewView addGestureRecognizer:pinch];

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

    self.zoomHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.zoomHintLabel.text = @"双指缩放可调整焦距";
    self.zoomHintLabel.textAlignment = NSTextAlignmentCenter;
    self.zoomHintLabel.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    self.zoomHintLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    [self.view addSubview:self.zoomHintLabel];

    self.switchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.switchButton setImage:[self loadSwitchImage] forState:UIControlStateNormal];
    self.switchButton.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.switchButton.imageEdgeInsets = UIEdgeInsetsMake(8, 8, 8, 8);
    self.switchButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    self.switchButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.4].CGColor;
    self.switchButton.layer.borderWidth = 1.0;
    self.switchButton.accessibilityLabel = @"切换前后摄像头";
    self.switchButton.enabled = NO;
    [self.switchButton addTarget:self action:@selector(switchCamera) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.switchButton];

    if (self.guideImageView.image == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithErrorCode:@"GUIDE_IMAGE_MISSING" message:@"人脸引导图资源缺失"];
        });
    }
}

- (UIImage *)resourceImageNamed:(NSString *)name fallbackBase64:(NSString *)fallbackBase64 {
    NSMutableArray<NSBundle *> *bundles = [NSMutableArray array];
    NSBundle *classBundle = [NSBundle bundleForClass:self.class];
    if (classBundle != nil) {
        [bundles addObject:classBundle];
    }
    if (![bundles containsObject:NSBundle.mainBundle]) {
        [bundles addObject:NSBundle.mainBundle];
    }
    NSString *frameworksPath = NSBundle.mainBundle.privateFrameworksPath;
    if (frameworksPath.length > 0) {
        NSBundle *frameworkBundle = [NSBundle bundleWithPath:
            [frameworksPath stringByAppendingPathComponent:@"UniFaceCapture.framework"]];
        if (frameworkBundle != nil && ![bundles containsObject:frameworkBundle]) {
            [bundles addObject:frameworkBundle];
        }
    }
    for (NSBundle *bundle in bundles) {
        NSString *path = [bundle pathForResource:name ofType:@"png"];
        UIImage *image = path.length > 0 ? [UIImage imageWithContentsOfFile:path] : nil;
        if (image != nil) {
            return image;
        }
    }
    UIImage *namedImage = [UIImage imageNamed:name];
    if (namedImage != nil) {
        return namedImage;
    }
    NSData *data = [[NSData alloc] initWithBase64EncodedString:fallbackBase64 options:0];
    return data.length > 0 ? [UIImage imageWithData:data] : nil;
}

- (UIImage *)loadGuideImage {
    return [self resourceImageNamed:@"face_guide_overlay" fallbackBase64:LQFaceGuideBase64];
}

- (UIImage *)loadSwitchImage {
    UIImage *image = [self resourceImageNamed:@"camera_switch" fallbackBase64:LQFaceSwitchBase64];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
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
        AVCaptureDevice *camera = [self cameraForPosition:self.cameraPosition];
        if (camera == nil) {
            self.cameraPosition = AVCaptureDevicePositionFront;
            camera = [self cameraForPosition:self.cameraPosition];
        }
        if (camera == nil) {
            [self finishWithErrorCode:@"CAMERA_UNAVAILABLE" message:@"设备没有可用的摄像头"];
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
        self.videoInput = input;
        self.photoOutput = output;

        dispatch_async(dispatch_get_main_queue(), ^{
            self.previewLayer.session = session;
            [self updatePreviewOrientation];
        });
        [session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.shutterButton.enabled = session.isRunning && !self.resolved;
            self.shutterButton.alpha = self.shutterButton.enabled ? 1.0 : 0.5;
            self.switchButton.enabled = self.shutterButton.enabled;
            self.switchButton.alpha = self.switchButton.enabled ? 1.0 : 0.5;
        });
    });
}

- (AVCaptureDevice *)cameraForPosition:(AVCaptureDevicePosition)position {
    return [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
        mediaType:AVMediaTypeVideo position:position];
}

/** Replaces the active camera input without rebuilding the preview or overlay UI. */
- (void)switchCamera {
    if (self.capturing || self.session == nil || self.videoInput == nil) {
        return;
    }
    AVCaptureDevicePosition targetPosition = self.cameraPosition == AVCaptureDevicePositionBack
        ? AVCaptureDevicePositionFront
        : AVCaptureDevicePositionBack;
    AVCaptureDevice *targetCamera = [self cameraForPosition:targetPosition];
    if (targetCamera == nil) {
        return;
    }
    self.switchButton.enabled = NO;
    self.switchButton.alpha = 0.5;
    dispatch_async(self.sessionQueue, ^{
        NSError *inputError = nil;
        AVCaptureDeviceInput *newInput = [AVCaptureDeviceInput deviceInputWithDevice:targetCamera error:&inputError];
        if (newInput == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.switchButton.enabled = YES;
                self.switchButton.alpha = 1.0;
            });
            return;
        }
        AVCaptureDeviceInput *oldInput = self.videoInput;
        [self.session beginConfiguration];
        [self.session removeInput:oldInput];
        if ([self.session canAddInput:newInput]) {
            [self.session addInput:newInput];
            self.videoInput = newInput;
            self.cameraPosition = targetPosition;
        } else if ([self.session canAddInput:oldInput]) {
            [self.session addInput:oldInput];
        }
        [self.session commitConfiguration];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updatePreviewOrientation];
            self.switchButton.enabled = !self.resolved;
            self.switchButton.alpha = self.switchButton.enabled ? 1.0 : 0.5;
        });
    });
}

/** Applies continuous optical/digital zoom from an incremental pinch gesture. */
- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (self.capturing || self.videoInput.device == nil) {
        return;
    }
    AVCaptureDevice *device = self.videoInput.device;
    NSError *lockError = nil;
    if (![device lockForConfiguration:&lockError]) {
        return;
    }
    CGFloat maximumZoom = MIN(device.activeFormat.videoMaxZoomFactor, 6.0);
    CGFloat zoom = MIN(MAX(device.videoZoomFactor * gesture.scale, 1.0), maximumZoom);
    device.videoZoomFactor = zoom;
    [device unlockForConfiguration];
    gesture.scale = 1.0;
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
            self.switchButton.enabled = session.isRunning;
            self.switchButton.alpha = session.isRunning ? 1.0 : 0.5;
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
        connection.videoMirrored = self.cameraPosition == AVCaptureDevicePositionFront;
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
    self.switchButton.enabled = NO;
    self.switchButton.alpha = 0.5;
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
        self.switchButton.enabled = self.session.isRunning;
        self.switchButton.alpha = self.switchButton.enabled ? 1.0 : 0.5;
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
