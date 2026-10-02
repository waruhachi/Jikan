#import "JikanStackController.h"

@interface JikanStackController ()
@property (nonatomic, strong) UITableView *stackTable;
@property (nonatomic, strong) NSMutableArray<NSString *> *activeItems;
@end

@implementation JikanStackController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = JikanLocalizedString(@"jikan.prefs.row.stack", @"Stack");
	self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
	UITableView *table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
	table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	table.dataSource = self;
	table.delegate = self;
	table.allowsSelectionDuringEditing = YES;
	[self.view addSubview:table];
	self.stackTable = table;
	[table setEditing:YES animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	self.activeItems = [JikanStackItems(prefs) mutableCopy];
	[self.stackTable reloadData];
}

- (NSArray<NSString *> *)_availableItems {
	NSMutableArray<NSString *> *available = [NSMutableArray array];
	for (NSString *item in @[JikanStackWattage, JikanStackTemperature, JikanStackVoltage]) {
		if (![self.activeItems containsObject:item]) [available addObject:item];
	}
	return available;
}

- (void)_saveItems {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	[prefs setObject:JikanNormalizeStackItems(self.activeItems) forKey:JikanStackItemsKey];
	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
}

- (NSString *)_nameForItem:(NSString *)item {
	if ([item isEqualToString:JikanStackEstimate]) return JikanLocalizedString(@"jikan.stack.item.estimate", @"Estimated Time");
	if ([item isEqualToString:JikanStackWattage]) return JikanLocalizedString(@"jikan.stack.item.wattage", @"Wattage");
	if ([item isEqualToString:JikanStackTemperature]) return JikanLocalizedString(@"jikan.stack.item.temperature", @"Temperature");
	return JikanLocalizedString(@"jikan.stack.item.voltage", @"Voltage");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
#pragma unused(tableView)
	return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
#pragma unused(tableView)
	if (section == 0) return self.activeItems.count;
	if (section == 1) return [self _availableItems].count;
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
#pragma unused(tableView)
	if (section == 0) return JikanLocalizedString(@"jikan.stack.section.active", @"Active");
	if (section == 1) return JikanLocalizedString(@"jikan.stack.section.available", @"Available");
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StackItem"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"StackItem"];
	NSString *item = indexPath.section == 0 ? self.activeItems[indexPath.row] : [self _availableItems][indexPath.row];
	cell.textLabel.text = [self _nameForItem:item];
	BOOL hasSettings = [item isEqualToString:JikanStackTemperature];
	cell.selectionStyle = hasSettings ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	cell.accessoryType = hasSettings ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.editingAccessoryType = hasSettings ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.showsReorderControl = indexPath.section == 0 && indexPath.row > 0;
	return cell;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
#pragma unused(tableView)
	if (indexPath.section == 0) return indexPath.row == 0 ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete;
	return indexPath.section == 1 ? UITableViewCellEditingStyleInsert : UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
#pragma unused(tableView, indexPath)
	return NO;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0 && indexPath.row > 0 && style == UITableViewCellEditingStyleDelete) {
		[self.activeItems removeObjectAtIndex:indexPath.row];
	} else if (indexPath.section == 1 && style == UITableViewCellEditingStyleInsert) {
		NSString *item = [self _availableItems][indexPath.row];
		[self.activeItems addObject:item];
	} else
		return;
	[self _saveItems];
	[tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
#pragma unused(tableView)
	return indexPath.section == 0 && indexPath.row > 0;
}

- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
#pragma unused(tableView, source)
	if (proposed.section != 0 || proposed.row < 1) return [NSIndexPath indexPathForRow:1 inSection:0];
	return proposed;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
#pragma unused(tableView)
	NSString *item = self.activeItems[source.row];
	[self.activeItems removeObjectAtIndex:source.row];
	[self.activeItems insertObject:item atIndex:destination.row];
	[self _saveItems];
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
#pragma unused(tableView)
	NSString *item = indexPath.section == 0 ? self.activeItems[indexPath.row] : [self _availableItems][indexPath.row];
	return [item isEqualToString:JikanStackTemperature] ? indexPath : nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	JikanStackItemController *controller = [[JikanStackItemController alloc] init];
	[self pushController:controller];
}

@end
