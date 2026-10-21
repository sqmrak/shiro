#import "shiro_menus.h"
#import "app_common.h"
#import "ui_theme.h"
#import "text_prompt.h"

@interface ShiroNetworksVC : ShiroTableController {
    NSString *_key;
    NSDictionary *_snapshot;
    NSArray *_networks;
    BOOL _saving;
}
- (id)initWithControl:(ShiroControl *)control key:(NSString *)key;
@end

@interface ShiroRoutingVC () {
    NSDictionary *_snapshot;
}
@end
@implementation ShiroRoutingVC
- (void)dealloc { [_snapshot release]; [super dealloc]; }
- (NSString *)devTitle { return ShiroLocalizedText(@"Routing"); }
- (const char *)devScreenName { return "routing"; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_ctl request:[NSDictionary dictionaryWithObject:@"status" forKey:@"command"] reply:^(NSDictionary *response, NSString *error) {
        [_snapshot release]; _snapshot = error ? nil : [response copy]; [_tv reloadData];
    }];
}
- (NSString *)devHeaderForSection:(NSInteger)section { return ShiroLocalizedText(section == 0 ? @"Rules" : @"DNS"); }
- (NSString *)devFooterForSection:(NSInteger)section {
    return ShiroLocalizedText(section == 0 ? @"Unmatched IPv4 traffic uses WARP. Disconnect before changing rules. IPv6 is blocked while the tunnel is active." : @"The system resolver uses this IPv4 server through the tunnel.");
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : 1; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [self devCellForTable:tv indexPath:index rows:index.section == 0 ? 2 : 1];
    cell.textLabel.text = ShiroLocalizedText(index.section == 0 ? index.row == 0 ? @"Direct" : @"Block" : @"DNS");
    NSString *key = index.section == 0 ? index.row == 0 ? @"direct" : @"block" : @"dns";
    cell.detailTextLabel.text = [_snapshot objectForKey:key] ?: ShiroLocalizedText(@"Daemon is unreachable");
    if (index.section == 0 && !cell.detailTextLabel.text.length) cell.detailTextLabel.text = ShiroLocalizedText(@"No rules");
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = TintedIconNamed(index.section == 0 ? @"glyph-split.png" : @"glyph-shield.png", 24, kInk);
    ShiroStyleSelectableCell(cell); return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tv deselectRowAtIndexPath:index animated:YES];
    if (index.section == 0) {
        ShiroNetworksVC *rules = [[[ShiroNetworksVC alloc] initWithControl:_ctl key:index.row == 0 ? @"direct" : @"block"] autorelease];
        [self.navigationController pushViewController:rules animated:YES]; return;
    }
    if (!_snapshot) { [self devSay:@"DNS" message:ShiroLocalizedText(@"Daemon is unreachable")]; return; }
    [ShiroTextPromptVC presentFrom:self title:@"DNS" message:ShiroLocalizedText(@"Upstream IPv4 address") text:[_snapshot objectForKey:@"dns"] keyboard:UIKeyboardTypeNumbersAndPunctuation confirm:ShiroLocalizedText(@"Save") handler:^(NSString *text) {
        NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:_snapshot];
        [request setObject:@"settings" forKey:@"command"]; [request setObject:text forKey:@"dns"];
        [_ctl request:request reply:^(NSDictionary *reply, NSString *error) {
            if (error) [self devSay:@"DNS" message:ShiroHumanReadableError(error)];
            else { [_snapshot release]; _snapshot = [reply copy]; [_tv reloadData]; }
        }];
    }];
}
@end

@implementation ShiroNetworksVC
- (id)initWithControl:(ShiroControl *)control key:(NSString *)key {
    if ((self = [super initWithControl:control])) _key = [key copy]; return self;
}
- (void)dealloc { [_key release]; [_snapshot release]; [_networks release]; [super dealloc]; }
- (NSString *)devTitle { return ShiroLocalizedText([_key isEqualToString:@"direct"] ? @"Direct" : @"Block"); }
- (const char *)devScreenName { return "network rules"; }
- (NSString *)devFooterForSection:(NSInteger)section { return ShiroLocalizedText(@"IPv4 network and prefix, for example 192.168.0.0/16. Swipe a rule to delete it."); }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(add)] autorelease];
}
- (void)useSnapshot:(NSDictionary *)snapshot {
    [_snapshot release]; _snapshot = [snapshot copy];
    NSMutableArray *list = [NSMutableArray array];
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@", \r\n\t"];
    for (NSString *part in [[snapshot objectForKey:_key] componentsSeparatedByCharactersInSet:separators]) if (part.length) [list addObject:part];
    [_networks release]; _networks = [list copy]; [_tv reloadData];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_ctl request:[NSDictionary dictionaryWithObject:@"status" forKey:@"command"] reply:^(NSDictionary *reply, NSString *error) {
        if (error) [self devSay:[self devTitle] message:ShiroHumanReadableError(error)]; else [self useSnapshot:reply];
    }];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section { return _networks.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [self devCellForTable:tv indexPath:index rows:_networks.count];
    cell.textLabel.text = [_networks objectAtIndex:index.row];
    cell.detailTextLabel.text = [self devTitle]; return cell;
}
- (void)save:(NSArray *)networks {
    if (_saving || !_snapshot) return;
    _saving = YES;
    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithDictionary:_snapshot];
    [request setObject:@"settings" forKey:@"command"]; [request setObject:[networks componentsJoinedByString:@"\n"] forKey:_key];
    [_ctl request:request reply:^(NSDictionary *reply, NSString *error) {
        _saving = NO;
        if (error) [self devSay:[self devTitle] message:ShiroHumanReadableError(error)]; else [self useSnapshot:reply];
    }];
}
- (void)add {
    if (!_snapshot || _saving) return;
    [ShiroTextPromptVC presentFrom:self title:ShiroLocalizedText(@"Add rule") message:ShiroLocalizedText(@"IPv4 network/prefix") text:@"" keyboard:UIKeyboardTypeNumbersAndPunctuation confirm:ShiroLocalizedText(@"Add") handler:^(NSString *text) {
        NSMutableArray *list = [[_networks mutableCopy] autorelease]; [list addObject:text]; [self save:list];
    }];
}
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)index { return !_saving; }
- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)index {
    if (style != UITableViewCellEditingStyleDelete || _saving) return;
    NSMutableArray *list = [[_networks mutableCopy] autorelease]; [list removeObjectAtIndex:index.row]; [self save:list];
}
@end
