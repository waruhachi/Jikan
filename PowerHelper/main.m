#import "main.h"

int main(int argc, char **argv) {
	@autoreleasepool {
		if (argc == 2 && strcmp(argv[1], "--configure") == 0) {
			if (getuid() != 0) return EXIT_FAILURE;
			NSString *path = jbroot(@"/Library/LaunchDaemons/moe.waru.jikan.input-power.plist");
			NSString *program = jbroot(@"/usr/libexec/JikanPowerd");
			NSDictionary *job = @{
				@"Label": JikanInputPowerServiceName,
				@"ProgramArguments": @[program],
				@"MachServices": @{JikanInputPowerServiceName: @YES},
				@"UserName": @"mobile",
				@"ProcessType": @"Background"
			};
			if (![job writeToFile:path atomically:YES] || chmod(path.fileSystemRepresentation, 0644) != 0) return EXIT_FAILURE;
			puts(path.fileSystemRepresentation);
			return EXIT_SUCCESS;
		}
		if (argc != 1) return EXIT_FAILURE;
		[[JikanPowerService new] run];
	}
	return EXIT_SUCCESS;
}
