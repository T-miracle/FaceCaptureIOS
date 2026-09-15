#import <UIKit/UIKit.h>

typedef void (^LQFaceCaptureCompletion)(NSDictionary *result);

/** Full-screen portrait front-camera flow that returns one square JPEG. */
@interface LQFaceCaptureViewController : UIViewController

- (instancetype)initWithCompletion:(LQFaceCaptureCompletion)completion;

@end
