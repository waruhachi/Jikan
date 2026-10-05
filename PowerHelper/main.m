#import "main.h"

int main(int argc, char **argv) {
	@autoreleasepool {
		if (argc == 2 && strcmp(argv[1], "--configure") == 0) {
			if (getuid() != 0) return EXIT_FAILURE;
			NSString *path = jbroot(@"/Library/LaunchDaemons/moe.waru.jikan.input-power.plist");
			NSString *program = jbroot(@"/usr/libexec/jikan-powerd");
			NSString *bootstrapPath = path;
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
			// RootHide's launchd plists and bootstrap tools use jbroot-based paths.
			// Do not persist its randomized physical root across re-jailbreaks.
			program = @"/usr/libexec/jikan-powerd";
			bootstrapPath = @"/Library/LaunchDaemons/moe.waru.jikan.input-power.plist";
#endif
			NSDictionary *job = @{
				@"Label": JikanInputPowerServiceName,
				@"ProgramArguments": @[program],
				@"MachServices": @{JikanInputPowerServiceName: @YES},
				@"UserName": @"mobile",
				@"ProcessType": @"Background"
			};
			if (![job writeToFile:path atomically:YES] || chmod(path.fileSystemRepresentation, 0644) != 0) return EXIT_FAILURE;
			puts(bootstrapPath.fileSystemRepresentation);
			return EXIT_SUCCESS;
		}
		if (argc != 1) return EXIT_FAILURE;
		[[JikanPowerService new] run];
	}
	return EXIT_SUCCESS;
}
