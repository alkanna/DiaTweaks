#import "CommandBar.h"

@implementation DPBarIcons {
    // Not NSCache: under memory pressure it evicted on every load, and each reload redrew, so icons flickered nonstop.
    NSMutableDictionary<NSString *, id> *_icons;  // NSNull for a miss. Guarded by self since preload runs off main.
    NSMutableSet<NSString *> *_loading;  // Main thread only.
    dispatch_queue_t _queue;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _icons = [NSMutableDictionary new];
    _loading = [NSMutableSet new];
    _queue = dispatch_queue_create("com.diapatches.commandbar.icons", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (void)prepare {
    @synchronized (self) { [_icons removeAllObjects]; }
}

- (id)cached:(NSString *)url {
    @synchronized (self) { return _icons[url]; }
}

static NSData *DPLargestIcon(NSString *space, NSString *where, NSArray<NSString *> *args) {
    __block NSData *png = nil;
    NSString *sql = [NSString stringWithFormat:@"SELECT b.image_data FROM icon_mapping m JOIN favicon_bitmaps b ON b.icon_id = m.icon_id "
                                                "WHERE %@ AND length(b.image_data) > 0 ORDER BY b.width DESC LIMIT 1", where];
    DPBarQueryProfile(space, @"Favicons", sql, args, ^(NSArray *columns) {
        if ([columns[0] isKindOfClass:NSData.class]) png = columns[0];
    });
    return png;
}

// Both queries can use the page_url index. "0" sorts right after "/".
static NSData *DPIconData(NSString *url, NSString *space) {
    NSURLComponents *parts = [NSURLComponents componentsWithString:url];
    NSData *png = parts.path.length ? DPLargestIcon(space, @"m.page_url = ?1", @[url]) : nil;  // Chromium stores "https://a.io/", not "https://a.io".
    if (png.length || !parts.host.length || !parts.scheme.length) return png;
    NSString *host = parts.host.lowercaseString;
    NSString *other = [host hasPrefix:@"www."] ? [host substringFromIndex:4] : [@"www." stringByAppendingString:host];
    NSString *port = parts.port ? [@":" stringByAppendingString:parts.port.stringValue] : @"";
    for (NSString *candidate in @[host, other]) {
        NSString *site = [NSString stringWithFormat:@"%@://%@%@", parts.scheme.lowercaseString, candidate, port];
        png = DPLargestIcon(space, @"m.page_url >= ?1 AND m.page_url < ?2", @[[site stringByAppendingString:@"/"], [site stringByAppendingString:@"0"]]);
        if (png.length) return png;
    }
    return nil;
}

- (void)preload:(NSString *)url space:(NSString *)space {
    if (self.disabled || !url.length || [self cached:url]) return;
    NSData *png = DPIconData(url, space);
    NSImage *image = png.length ? [[NSImage alloc] initWithData:png] : nil;
    @synchronized (self) { _icons[url] = image ?: NSNull.null; }
}

- (NSImage *)iconFor:(NSString *)url space:(NSString *)space {
    if (self.disabled || !url.length) return nil;
    id cached = [self cached:url];
    if (cached || [_loading containsObject:url]) return [cached isKindOfClass:NSImage.class] ? cached : nil;
    [_loading addObject:url];
    dispatch_async(_queue, ^{
        [self preload:url space:space];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_loading removeObject:url];
            if ([[self cached:url] isKindOfClass:NSImage.class] && self.changed) self.changed();
        });
    });
    return nil;
}

@end
