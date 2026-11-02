#import "JikanStackController.h"
#import "JikanStackEstimateController.h"
#import "../../Shared/JikanEstimateSettings.h"

@interface JikanStackController ()
@property (nonatomic, strong) UITableView *stackTable;
@property (nonatomic, strong) NSMutableArray<JikanStackItem *> *activeItems;
@property (nonatomic) NSInteger mainTarget;
@property (nonatomic) BOOL apple;
@end

@implementation JikanStackController
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = JikanLocalizedString(@"jikan.prefs.row.stack", @"Stack");
	UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	table.dataSource = self;
	table.delegate = self;
	table.rowHeight = UITableViewAutomaticDimension;
	table.estimatedRowHeight = 55;
	table.allowsSelectionDuringEditing = YES;
	self.stackTable = table;
	self.view = table;
	[table setEditing:YES animated:NO];
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	self.activeItems = [JikanStackItems(prefs) mutableCopy];
	NSString *source = JikanEstimateSource(prefs);
	self.apple = [source isEqualToString:@"apple"];
	self.mainTarget = JikanEstimateTarget(prefs, source);
	[self.stackTable reloadData];
}
- (NSArray<JikanStackItem *> *)_availableItems {
	NSMutableArray *available = [NSMutableArray array];
	for (NSString *type in @[JikanStackWattage, JikanStackTemperature, JikanStackVoltage]) {
		BOOL present = NO;
		for (JikanStackItem *item in self.activeItems) if ([item.type isEqual:type]) { present = YES; break; }
		if (!present) [available addObject:[[JikanStackItem alloc] initWithIdentifier:type type:type targetPercent:nil]];
	}
	return available;
}
- (BOOL)_canAddEstimate {
	return JikanAvailableStackTargets(self.activeItems, self.mainTarget, self.apple ? @"apple" : @"jikan", nil).count > 0;
}
- (JikanStackItem *)_itemAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) return self.activeItems[indexPath.row];
	NSArray *available = [self _availableItems];
	return indexPath.row < available.count ? available[indexPath.row] : nil;
}
- (void)_saveItems {
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	[prefs setObject:JikanStackPropertyList(self.activeItems) forKey:JikanStackItemsKey];
	[prefs synchronize];
	CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)JikanPreferencesReloadNotification, NULL, NULL, YES);
}
- (void)_editEstimate:(JikanStackItem *)item {
	__weak typeof(self) weakSelf = self;
	JikanStackEstimateController *controller = [[JikanStackEstimateController alloc] initWithItem:item items:self.activeItems saveHandler:^(JikanStackItem *saved) {
		__strong typeof(weakSelf) self = weakSelf;
		if (!self) return;
		NSUInteger index = NSNotFound;
		for (NSUInteger i = 0; i < self.activeItems.count; i++) if ([self.activeItems[i].identifier isEqual:saved.identifier]) { index = i; break; }
		if (index == NSNotFound) [self.activeItems addObject:saved];
		else self.activeItems[index] = saved;
		[self _saveItems];
		[self.stackTable reloadData];
	}];
	[self pushController:controller];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? self.activeItems.count : [self _availableItems].count + 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? JikanLocalizedString(@"jikan.stack.section.active", @"Active") : JikanLocalizedString(@"jikan.stack.section.available", @"Available");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StackItem"];
	if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"StackItem"];
	JikanStackItem *item = [self _itemAtIndexPath:indexPath];
	cell.textLabel.text = item ? JikanStackItemName(item, self.mainTarget) : JikanLocalizedString(@"jikan.stack.action.add_estimate", @"Add Estimate");
	cell.detailTextLabel.text = nil;
	if (item.isMainEstimate) cell.detailTextLabel.text = [NSString stringWithFormat:JikanLocalizedString(@"jikan.stack.target.main", @"Main target: %ld%%"), (long)self.mainTarget];
	else if (item.isEstimate && self.apple && !JikanAppleTargetIsSupported(item.targetPercent.integerValue)) cell.detailTextLabel.text = [NSString stringWithFormat:JikanLocalizedString(@"jikan.stack.target.unsupported", @"%ld%% is unavailable with Apple estimates"), (long)item.targetPercent.integerValue];
	BOOL editable = (!item && [self _canAddEstimate]) || (item.isEstimate && !item.isMainEstimate) || [item.type isEqual:JikanStackTemperature];
	cell.selectionStyle = editable ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
	cell.accessoryType = editable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
	cell.editingAccessoryType = cell.accessoryType;
	cell.showsReorderControl = indexPath.section == 0 && indexPath.row > 0;
	cell.textLabel.enabled = item != nil || [self _canAddEstimate];
	cell.textLabel.adjustsFontForContentSizeCategory = YES;
	cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
	cell.textLabel.numberOfLines = 0;
	cell.detailTextLabel.numberOfLines = 0;
	return cell;
}
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) return indexPath.row == 0 ? UITableViewCellEditingStyleNone : UITableViewCellEditingStyleDelete;
	return [self _itemAtIndexPath:indexPath] || [self _canAddEstimate] ? UITableViewCellEditingStyleInsert : UITableViewCellEditingStyleNone;
}
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath { return NO; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0 && indexPath.row > 0 && style == UITableViewCellEditingStyleDelete) [self.activeItems removeObjectAtIndex:indexPath.row];
	else if (indexPath.section == 1 && style == UITableViewCellEditingStyleInsert) {
		JikanStackItem *item = [self _itemAtIndexPath:indexPath];
		if (!item) { if ([self _canAddEstimate]) [self _editEstimate:nil]; return; }
		[self.activeItems addObject:item];
	} else return;
	[self _saveItems];
	[tableView reloadData];
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 0 && indexPath.row > 0; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)proposed {
	if (proposed.section != 0 || proposed.row < 1) return [NSIndexPath indexPathForRow:1 inSection:0];
	return proposed;
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
	JikanStackItem *item = self.activeItems[source.row];
	[self.activeItems removeObjectAtIndex:source.row];
	[self.activeItems insertObject:item atIndex:destination.row];
	[self _saveItems];
}
- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	JikanStackItem *item = [self _itemAtIndexPath:indexPath];
	return ((!item && [self _canAddEstimate]) || (item.isEstimate && !item.isMainEstimate) || [item.type isEqual:JikanStackTemperature]) ? indexPath : nil;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	JikanStackItem *item = [self _itemAtIndexPath:indexPath];
	if (!item || item.isEstimate) [self _editEstimate:item];
	else [self pushController:[JikanStackItemController new]];
}
@end
