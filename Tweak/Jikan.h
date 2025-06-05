#include <spawn.h>
#include <UIKit/UIKit.h>
#include <IOKit/IOKitLib.h>
#include <Foundation/Foundation.h>
#include <SpringBoard/SpringBoard.h>

#include "Battery/Battery.h"

@interface _UIBatteryView : UIView
@end

@interface CSCoverSheetView : UIView
@end

@interface NCNotificationListCountIndicatorView : UIView
@end

@interface MTMaterialView : UIView
	@property (nonatomic, assign, readwrite) BOOL captureOnly;

	- (void)setRecipe:(NSInteger)recipe;
	+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe options:(NSUInteger)options;
	+ (MTMaterialView *)materialViewWithRecipe:(NSInteger)recipe configuration:(NSInteger)configuration;
@end

extern BOOL isCharging;
extern NSString *chargingstate;
