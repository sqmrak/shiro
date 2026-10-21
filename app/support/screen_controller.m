#import "screen_controller.h"

@implementation ShiroScreenController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad ||
           orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (BOOL)shouldAutorotate { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
#else
- (NSUInteger)supportedInterfaceOrientations {
#endif
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad
        ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskAllButUpsideDown;
}
@end
