#import "JikanStackEstimateController.h"
#import "JikanSliderSettings.h"
#import "../../Shared/JikanEstimateSettings.h"
#import "../../Shared/JikanPreferences.h"
#import "../../Localization/JikanLocalization.h"

// Keep UISlider's native presentation, with the same target steps for touch
// and VoiceOver adjustments (1% for Jikan, 5% for Apple's presets).
@interface JikanStackTargetSlider : UISlider
@property (nonatomic) NSInteger targetStep;
@end
@implementation JikanStackTargetSlider
- (void)accessibilityIncrement {
	self.value = MIN(self.maximumValue, self.value + self.targetStep);
	[self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)accessibilityDecrement {
	self.value = MAX(self.minimumValue, self.value - self.targetStep);
	[self sendActionsForControlEvents:UIControlEventValueChanged];
}
@end

@interface JikanStackEstimateController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *settingsTable;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) JikanStackItem *item;
@property (nonatomic, copy) NSArray<JikanStackItem *> *items;
@property (nonatomic, copy) void (^saveHandler)(JikanStackItem *);
@property (nonatomic) NSInteger targetPercent;
@property (nonatomic) BOOL apple;
@property (nonatomic) NSInteger mainTarget;
@property (nonatomic, weak) UIAlertController *numberAlert;
@end

@implementation JikanStackEstimateController
- (instancetype)initWithItem:(JikanStackItem *)item items:(NSArray<JikanStackItem *> *)items saveHandler:(void (^)(JikanStackItem *))saveHandler {
	if ((self = [super init])) {
		_item = item;
		_items = [items copy];
		_saveHandler = [saveHandler copy];
		NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
		NSString *source = JikanEstimateSource(prefs);
		_mainTarget = JikanEstimateTarget(prefs, source);
		_apple = [source isEqualToString:@"apple"];
		_targetPercent = item.targetPercent ? item.targetPercent.integerValue : 100;
		if (!item && ![self _isValidTarget:_targetPercent]) for (NSInteger value = _apple ? 80 : 1; value <= 100; value += _apple ? 5 : 1) {
			if ([self _isValidTarget:value]) { _targetPercent = value; break; }
		}
	}
	return self;
}
- (void)loadView {
	UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	table.dataSource = self;
	table.delegate = self;
	table.rowHeight = UITableViewAutomaticDimension;
	table.estimatedRowHeight = 55;
	self.settingsTable = table;
	self.view = table;
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = JikanLocalizedString(@"jikan.stack.item.estimate", @"Estimated Time");
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave target:self action:@selector(_save)];
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:JikanPreferencesSuite];
	NSString *source = JikanEstimateSource(prefs);
	self.apple = [source isEqualToString:@"apple"];
	self.mainTarget = JikanEstimateTarget(prefs, source);
	self.navigationItem.rightBarButtonItem.enabled = [self _isValidTarget:self.targetPercent];
	[self.settingsTable reloadData];
}
- (BOOL)_isValidTarget:(NSInteger)target {
	return [JikanAvailableStackTargets(self.items, self.mainTarget, self.apple ? @"apple" : @"jikan", self.item.identifier) containsObject:@(target)];
}
- (void)_save {
	if (![self _isValidTarget:self.targetPercent]) return;
	JikanStackItem *item = self.item ? [[JikanStackItem alloc] initWithIdentifier:self.item.identifier type:JikanStackEstimate targetPercent:@(self.targetPercent)] : [JikanStackItem estimateWithTargetPercent:self.targetPercent];
	if (self.saveHandler) self.saveHandler(item);
	[self.navigationController popViewControllerAnimated:YES];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (self.apple && !JikanAppleTargetIsSupported(self.targetPercent)) return [NSString stringWithFormat:JikanLocalizedString(@"jikan.stack.target.unsupported", @"%ld%% is unavailable with Apple estimates"), (long)self.targetPercent];
	if (![self _isValidTarget:self.targetPercent]) return JikanLocalizedString(@"jikan.stack.target.duplicate", @"This target is already used by the main estimate or another Stack estimate.");
	return JikanLocalizedString(@"jikan.stack.target.hint", @"Choose a different target for this estimate. The pill advances to the next higher unfinished target when the displayed target is reached.");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	if (indexPath.row == 0) {
		cell.textLabel.text = JikanLocalizedString(@"jikan.prefs.row.estimate_target", @"Estimate Target");
		cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld%%", (long)self.targetPercent];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.textLabel.adjustsFontForContentSizeCategory = YES;
		cell.textLabel.numberOfLines = 0;
	} else {
		JikanStackTargetSlider *slider = [JikanStackTargetSlider new];
		slider.targetStep = self.apple ? 5 : 1;
		slider.minimumValue = self.apple ? 80 : 1;
		slider.maximumValue = 100;
		slider.value = self.targetPercent;
		slider.accessibilityValue = [NSString stringWithFormat:@"%ld%%", (long)self.targetPercent];
		slider.accessibilityLabel = JikanLocalizedString(@"jikan.prefs.row.estimate_target_percent", @"Estimate Target (%)");
		[slider addTarget:self action:@selector(_sliderChanged:) forControlEvents:UIControlEventValueChanged];
		slider.translatesAutoresizingMaskIntoConstraints = NO;
		[cell.contentView addSubview:slider];
		[NSLayoutConstraint activateConstraints:@[[slider.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor], [slider.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor], [slider.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12], [slider.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12]]];
		self.slider = slider;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	return cell;
}
- (void)_setTarget:(NSInteger)target {
	self.targetPercent = target;
	self.slider.value = target;
	self.slider.accessibilityValue = [NSString stringWithFormat:@"%ld%%", (long)target];
	self.navigationItem.rightBarButtonItem.enabled = [self _isValidTarget:target];
	[self.settingsTable footerViewForSection:0].textLabel.text = [self tableView:self.settingsTable titleForFooterInSection:0];
	[self.settingsTable reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}
- (void)_sliderChanged:(UISlider *)slider {
	[self _setTarget:self.apple ? 80 + 5 * (NSInteger)llround((slider.value - 80) / 5) : (NSInteger)llround(slider.value)];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.row != 0) return;
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:JikanLocalizedString(@"jikan.prefs.row.estimate_target", @"Estimate Target") message:JikanLocalizedString(@"jikan.stack.target.unique", @"Enter an unused target. Apple estimates support 80, 85, 90, 95, and 100%. Jikan estimates support 1–100%.") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.keyboardType = UIKeyboardTypeNumberPad;
		field.text = [NSString stringWithFormat:@"%ld", (long)self.targetPercent];
		[field addTarget:self action:@selector(_numberChanged:) forControlEvents:UIControlEventEditingChanged];
	}];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.cancel", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:JikanLocalizedString(@"jikan.common.action.save", @"Save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		double value = 0;
		if (JikanParseNumber(weakSelf.numberAlert.textFields.firstObject.text, NSLocale.currentLocale, &value)) [weakSelf _setTarget:(NSInteger)value];
	}]];
	self.numberAlert = alert;
	[self _numberChanged:alert.textFields.firstObject];
	[self presentViewController:alert animated:YES completion:nil];
}
- (void)_numberChanged:(UITextField *)field {
	double value = 0;
	BOOL valid = JikanParseNumber(field.text, NSLocale.currentLocale, &value) && isfinite(value) && floor(value) == value && value >= 1 && value <= 100 && [self _isValidTarget:(NSInteger)value];
	self.numberAlert.actions.lastObject.enabled = valid;
}
@end
