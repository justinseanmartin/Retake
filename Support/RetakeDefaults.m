// UserDefaults.standard for a take. In clean and cloned, it's replaced by a store in memory, which
// the app reads and writes as it always does; nothing reaches the real defaults, and everything is
// gone when the app quits. In live, the set's defaults are written into the real ones instead.
//
// A key is looked for as the real defaults look: launch arguments first, then the take's values
// (the set's, and what the take writes), then, in cloned only, the app's real values, read through
// without being copied or changed; then the global domain, then registered defaults. A key the take
// removes stays removed, rather than falling back to the real value.
#import "RetakeSupport.h"
#import <objc/runtime.h>

@interface RetakeDefaultsStore : NSUserDefaults
@end

@interface RetakeObservation : NSObject
@property (nonatomic, weak) NSObject *observer;
@property (nonatomic, copy) NSString *keyPath;
@property (nonatomic) NSKeyValueObservingOptions options;
@property (nonatomic) void *context;
@end

@implementation RetakeObservation
@end

@implementation RetakeDefaultsStore {
    NSMutableDictionary<NSString *, id> *_values;
    NSMutableSet<NSString *> *_removed;
    NSMutableDictionary<NSString *, id> *_registered;
    NSDictionary<NSString *, id> *_arguments;
    NSDictionary<NSString *, id> *_global;
    /// The real defaults, read through in cloned; nil in clean.
    NSUserDefaults *_real;
    NSMutableArray<RetakeObservation *> *_observations;
    NSRecursiveLock *_lock;
}

- (instancetype)initWithValues:(NSDictionary *)values real:(NSUserDefaults *)real readThrough:(BOOL)readThrough {
    self = [super initWithSuiteName:@"com.retake.take.unused"];
    if (self) {
        _values = [values mutableCopy] ?: [NSMutableDictionary new];
        _removed = [NSMutableSet new];
        _registered = [NSMutableDictionary new];
        _arguments = [real volatileDomainForName:NSArgumentDomain] ?: @{};
        _global = [real persistentDomainForName:NSGlobalDomain] ?: @{};
        _real = readThrough ? real : nil;
        _observations = [NSMutableArray new];
        _lock = [NSRecursiveLock new];
    }
    return self;
}

#pragma mark Reads

- (id)objectForKey:(NSString *)key {
    if (key == nil) return nil;
    [_lock lock];
    id value = _arguments[key];
    if (!value && ![_removed containsObject:key]) {
        value = _values[key];
        if (!value && _real) value = [[_real persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] objectForKey:key];
    }
    if (!value) value = _global[key] ?: _registered[key];
    [_lock unlock];
    return value;
}

- (NSString *)stringForKey:(NSString *)key {
    id value = [self objectForKey:key];
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return nil;
}

- (NSArray *)arrayForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

- (NSArray<NSString *> *)stringArrayForKey:(NSString *)key {
    NSArray *array = [self arrayForKey:key];
    for (id item in array) if (![item isKindOfClass:NSString.class]) return nil;
    return array;
}

- (NSDictionary *)dictionaryForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

- (NSData *)dataForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:NSData.class] ? value : nil;
}

- (NSURL *)URLForKey:(NSString *)key {
    id value = [self objectForKey:key];
    if ([value isKindOfClass:NSURL.class]) return value;
    if ([value isKindOfClass:NSData.class]) {
        NSURL *url = [NSKeyedUnarchiver unarchivedObjectOfClass:NSURL.class fromData:value error:nil];
        if (url) return url;
    }
    if ([value isKindOfClass:NSString.class]) {
        NSString *path = [value stringByExpandingTildeInPath];
        return [path hasPrefix:@"/"] ? [NSURL fileURLWithPath:path] : [NSURL URLWithString:value];
    }
    return nil;
}

- (BOOL)boolForKey:(NSString *)key {
    id value = [self objectForKey:key];
    if ([value isKindOfClass:NSString.class]) return [value boolValue];
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

- (NSInteger)integerForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

- (double)doubleForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}

- (float)floatForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value respondsToSelector:@selector(floatValue)] ? [value floatValue] : 0;
}

- (NSDictionary<NSString *, id> *)dictionaryRepresentation {
    [_lock lock];
    NSMutableDictionary *all = [_registered mutableCopy];
    [all addEntriesFromDictionary:_global];
    if (_real) [all addEntriesFromDictionary:[_real persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] ?: @{}];
    [all removeObjectsForKeys:_removed.allObjects];
    [all addEntriesFromDictionary:_values];
    [all addEntriesFromDictionary:_arguments];
    [_lock unlock];
    return all;
}

#pragma mark Writes

- (void)setObject:(id)value forKey:(NSString *)key {
    if (value == nil) {
        [self removeObjectForKey:key];
        return;
    }
    [self change:key to:value];
}

- (void)removeObjectForKey:(NSString *)key {
    [self change:key to:nil];
}

- (void)setBool:(BOOL)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setInteger:(NSInteger)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setFloat:(float)value forKey:(NSString *)key { [self setObject:@(value) forKey:key]; }
- (void)setURL:(NSURL *)url forKey:(NSString *)key { [self setObject:url.absoluteString forKey:key]; }

- (void)registerDefaults:(NSDictionary<NSString *, id> *)registrationDictionary {
    [_lock lock];
    [_registered addEntriesFromDictionary:registrationDictionary];
    [_lock unlock];
}

- (BOOL)synchronize { return YES; }

/// Sets or removes the value, then tells KVO observers of the key and posts didChangeNotification,
/// as the real defaults do for a change in the process.
- (void)change:(NSString *)key to:(id)value {
    [_lock lock];
    id old = [self objectForKey:key];
    if (value) {
        _values[key] = value;
        [_removed removeObject:key];
    } else {
        [_values removeObjectForKey:key];
        [_removed addObject:key];
    }
    id now = [self objectForKey:key];
    NSArray *observations = [_observations copy];
    [_lock unlock];

    for (RetakeObservation *observation in observations) {
        NSObject *observer = observation.observer;
        if (!observer || ![observation.keyPath isEqualToString:key]) continue;
        NSMutableDictionary *change = [@{NSKeyValueChangeKindKey: @(NSKeyValueChangeSetting)} mutableCopy];
        if (observation.options & NSKeyValueObservingOptionNew) change[NSKeyValueChangeNewKey] = now ?: NSNull.null;
        if (observation.options & NSKeyValueObservingOptionOld) change[NSKeyValueChangeOldKey] = old ?: NSNull.null;
        [observer observeValueForKeyPath:key ofObject:self change:change context:observation.context];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:self];
}

#pragma mark KVO, handled here, since the real defaults observe CFPreferences, which this isn't

- (void)addObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath options:(NSKeyValueObservingOptions)options context:(void *)context {
    RetakeObservation *observation = [RetakeObservation new];
    observation.observer = observer;
    observation.keyPath = keyPath;
    observation.options = options;
    observation.context = context;
    [_lock lock];
    [_observations addObject:observation];
    [_lock unlock];
    if (options & NSKeyValueObservingOptionInitial) {
        id now = [self objectForKey:keyPath];
        [observer observeValueForKeyPath:keyPath ofObject:self change:@{NSKeyValueChangeKindKey: @(NSKeyValueChangeSetting), NSKeyValueChangeNewKey: now ?: NSNull.null} context:context];
    }
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath context:(void *)context {
    [_lock lock];
    NSUInteger index = [_observations indexOfObjectPassingTest:^BOOL(RetakeObservation *o, NSUInteger i, BOOL *stop) {
        return o.observer == observer && [o.keyPath isEqualToString:keyPath] && o.context == context;
    }];
    if (index != NSNotFound) [_observations removeObjectAtIndex:index];
    [_lock unlock];
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    [_lock lock];
    NSUInteger index = [_observations indexOfObjectPassingTest:^BOOL(RetakeObservation *o, NSUInteger i, BOOL *stop) {
        return o.observer == observer && [o.keyPath isEqualToString:keyPath];
    }];
    if (index != NSNotFound) [_observations removeObjectAtIndex:index];
    [_lock unlock];
}

@end

#pragma mark Setting up

static RetakeDefaultsStore *store;

static id RetakeStandardUserDefaults(id self, SEL _cmd) {
    return store;
}

void RetakeSetUpDefaults(NSDictionary<NSString *, NSString *> *environment) {
    NSString *state = environment[@"RETAKE_STATE"];
    NSString *json = environment[@"RETAKE_DEFAULTS"] ?: @"{}";
    id parsed = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    NSDictionary *values = [parsed isKindOfClass:NSDictionary.class] ? parsed : @{};
    NSUserDefaults *real = NSUserDefaults.standardUserDefaults;

    if ([state isEqualToString:@"live"]) {
        [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            [real setObject:value forKey:key];
        }];
        return;
    }
    store = [[RetakeDefaultsStore alloc] initWithValues:values real:real readThrough:[state isEqualToString:@"cloned"]];
    Method method = class_getClassMethod(NSUserDefaults.class, @selector(standardUserDefaults));
    method_setImplementation(method, (IMP)RetakeStandardUserDefaults);
}
