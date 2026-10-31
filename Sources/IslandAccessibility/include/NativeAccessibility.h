#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Internal UI validation reads only objects belonging to its own test window.
FOUNDATION_EXPORT NSArray *SIAXChildren(id element);
FOUNDATION_EXPORT NSString *SIAXText(id element);
FOUNDATION_EXPORT NSString * _Nullable SIAXRole(id element);
FOUNDATION_EXPORT NSRect SIAXFrame(id element);
FOUNDATION_EXPORT BOOL SIAXPress(id element);
FOUNDATION_EXPORT BOOL SIAXFocus(id element);
NS_ASSUME_NONNULL_END
