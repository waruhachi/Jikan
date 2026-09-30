#import "JikanStackItemController.h"

@interface JikanStackItemController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *settingsTable;
@end

@implementation JikanStackItemController

- (void)loadView {
	UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	table.dataSource = self;
	table.delegate = self;
	self.settingsTable = table;
	self.view = table;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = JikanLocalizedString(@"jikan.stack.item.temperature", @"Temperature");
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.settingsTable reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
#pragma unused(tableView)
	return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
#pragma unused(tableView, section)
	return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
#pragma unused(tableView, section)
	return JikanLocalizedString(@"jikan.stack.section.unit", @"Temperature Unit");
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TemperatureUnit"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"TemperatureUnit"];
	NSArray<NSString *> *values = @[@"celsius", @"fahrenheit"];
	NSArray<NSString *> *names = @[JikanLocalizedString(@"jikan.stack.unit.celsius", @"Celsius"), JikanLocalizedString(@"jikan.stack.unit.fahrenheit", @"Fahrenheit")];
	cell.textLabel.text = names[indexPath.row];
	NSString *selected = JikanResolvedTemperatureUnit([[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite]);
	BOOL checked = [selected isEqualToString:values[indexPath.row]];
	UIImage *checkImage = [UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightSemibold]];
	if (checked && checkImage) {
		UIImageView *check = [[UIImageView alloc] initWithImage:checkImage];
		check.frame = CGRectMake(0, 0, 22, 22);
		check.contentMode = UIViewContentModeCenter;
		check.tintColor = UIColor.systemBlueColor;
		cell.accessoryView = check;
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
		cell.accessoryView = nil;
		cell.accessoryType = checked ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	}
	cell.accessibilityTraits = UIAccessibilityTraitButton | (checked ? UIAccessibilityTraitSelected : 0);
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSArray<NSString *> *values = @[@"celsius", @"fahrenheit"];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	[prefs setObject:values[indexPath.row] forKey:JikanTemperatureUnitKey];
	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
	[tableView reloadData];
}

@end
