#import "JikanDeviceCapabilities.h"

BOOL JikanDeviceSupportsQuickActionButtons(void) {
	// Stock Lock Screen quick actions use the Face ID iPhone layout. Query
	// hardware support rather than the current visibility of its controls.
	return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone && MGGetBoolAnswer(CFSTR("PearlIDCapability"));
}
