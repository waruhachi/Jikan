#pragma once
// Host tests exercise Foundation models without accessing jailbreak paths.
#ifdef __OBJC__
#import <Foundation/Foundation.h>
static inline NSString *jbroot(NSString *path) { return path; }
#endif
