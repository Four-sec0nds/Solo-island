#import "NativeAccessibility.h"

NSArray *SIAXChildren(id element) {
    if (![element respondsToSelector:@selector(accessibilityChildren)]) return @[];
    NSArray *children = [(id<NSAccessibility>)element accessibilityChildren];
    return children ? (NSAccessibilityUnignoredChildren(children) ?: @[]) : @[];
}

NSString *SIAXText(id element) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    id<NSAccessibility> accessible = element;
    if ([element respondsToSelector:@selector(accessibilityLabel)] && accessible.accessibilityLabel)
        [parts addObject:accessible.accessibilityLabel];
    if ([element respondsToSelector:@selector(accessibilityTitle)] && accessible.accessibilityTitle)
        [parts addObject:accessible.accessibilityTitle];
    if ([element respondsToSelector:@selector(accessibilityHelp)] && accessible.accessibilityHelp)
        [parts addObject:accessible.accessibilityHelp];
    if ([element respondsToSelector:@selector(accessibilityValue)]) {
        id value = accessible.accessibilityValue;
        if ([value isKindOfClass:NSString.class]) [parts addObject:value];
    }
    return [parts componentsJoinedByString:@" | "];
}

NSString *SIAXRole(id element) {
    if (![element respondsToSelector:@selector(accessibilityRole)]) return nil;
    return [(id<NSAccessibility>)element accessibilityRole];
}

NSRect SIAXFrame(id element) {
    if (![element respondsToSelector:@selector(accessibilityFrame)]) return NSZeroRect;
    return [(id<NSAccessibility>)element accessibilityFrame];
}

BOOL SIAXPress(id element) {
    if (![element respondsToSelector:@selector(accessibilityPerformPress)]) return NO;
    if ([element respondsToSelector:@selector(isAccessibilityEnabled)] &&
        ![(id<NSAccessibility>)element isAccessibilityEnabled]) return NO;
    return [(id<NSAccessibility>)element accessibilityPerformPress];
}

BOOL SIAXFocus(id element) {
    if (![element respondsToSelector:@selector(setAccessibilityFocused:)]) return NO;
    [(id<NSAccessibility>)element setAccessibilityFocused:YES];
    return YES;
}
