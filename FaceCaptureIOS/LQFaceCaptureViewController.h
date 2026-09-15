#import <UIKit/UIKit.h>

typedef void (^LQFaceCaptureCompletion)(NSDictionary *result);

/** Full-screen portrait camera flow with pinch zoom and camera switching that returns one square JPEG. */
@interface LQFaceCaptureViewController : UIViewController

- (instancetype)initWithCompletion:(LQFaceCaptureCompletion)completion;

@end
