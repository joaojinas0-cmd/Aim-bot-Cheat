//
// AimBotCheat.mm
// iOS Dylib Cheat para Block Strike
// Arm64
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <math.h>
#include <pthread.h>
#include <unistd.h>

#define LOG_TAG "AimBotCheat"
#define LOGI(fmt, ...) NSLog(@"[%s] " fmt, LOG_TAG, ##__VA_ARGS__)
#define LOGE(fmt, ...) NSLog(@"[%s] ERRO: " fmt, LOG_TAG, ##__VA_ARGS__)

typedef struct { float x, y, z; } Vector3;
typedef struct { bool enabled; float fov; float aimSpeed; } AimBotConfig;

static AimBotConfig g_config = { true, 50.0f, 5.0f };
static pthread_mutex_t g_configMutex = PTHREAD_MUTEX_INITIALIZER;

static Vector3 Vector3Make(float x, float y, float z) { Vector3 v = {x, y, z}; return v; }
static Vector3 Vector3Subtract(Vector3 a, Vector3 b) { Vector3 v = {a.x-b.x, a.y-b.y, a.z-b.z}; return v; }
static Vector3 Vector3Normalize(Vector3 v) { float l=sqrt(v.x*v.x+v.y*v.y+v.z*v.z); Vector3 result = l>0?Vector3Make(v.x/l,v.y/l,v.z/l):v; return result; }

static id FindPlayerObject() {
    @try { return [NSClassFromString(@"UnityEngine.GameObject") performSelector:@selector(Find:) withObject:@"Player"]; }
    @catch (...) { return nil; }
}

static NSArray* FindEnemies() {
    @try { return [NSClassFromString(@"UnityEngine.Object") performSelector:@selector(FindObjectsOfType:) withObject:NSClassFromString(@"PlayerSkin")] ?: @[]; }
    @catch (...) { return @[]; }
}

static CGPoint WorldToScreenPoint(id camera, Vector3 worldPos) {
    @try {
        if (!camera) return CGPointZero;
        id vec3 = [[NSClassFromString(@"UnityEngine.Vector3") alloc] performSelector:@selector(initWithX:Y:Z:) 
                        withObject:@(worldPos.x) withObject:@(worldPos.y) withObject:@(worldPos.z)];
        id screen = [camera performSelector:@selector(WorldToScreenPoint:) withObject:vec3];
        if (!screen) return CGPointZero;
        return CGPointMake([[screen performSelector:@selector(get_x)] floatValue], [[screen performSelector:@selector(get_y)] floatValue]);
    } @catch (...) { return CGPointZero; }
}

static Vector3 GetWorldPosition(id obj) {
    @try {
        id pos = [[obj performSelector:@selector(get_transform)] performSelector:@selector(get_position)];
        if (!pos) return Vector3Make(0,0,0);
        return Vector3Make([[pos performSelector:@selector(get_x)] floatValue], [[pos performSelector:@selector(get_y)] floatValue], [[pos performSelector:@selector(get_z)] floatValue]);
    } @catch (...) { return Vector3Make(0,0,0); }
}

static void AimAtEnemy(id player, id enemy, float speed) {
    @try {
        if (!player || !enemy) return;
        Vector3 direction = Vector3Normalize(Vector3Subtract(GetWorldPosition(enemy), GetWorldPosition(player)));
        id transform = [player performSelector:@selector(get_transform)];
        if (!transform) return;
        id quaternion = [NSClassFromString(@"UnityEngine.Quaternion") performSelector:@selector(LookRotation:) withObject:[NSValue value:&direction withObjCType:@encode(Vector3)]];
        if (quaternion) [transform performSelector:@selector(set_rotation:) withObject:quaternion];
    } @catch (...) {}
}

static void* AimBotThread(void* arg) {
    LOGI("Thread iniciada");
    while (1) {
        @autoreleasepool {
            pthread_mutex_lock(&g_configMutex);
            bool enabled = g_config.enabled; float fov = g_config.fov; float aimSpeed = g_config.aimSpeed;
            pthread_mutex_unlock(&g_configMutex);
            if (!enabled) { usleep(100000); continue; }
            
            id player = FindPlayerObject(); NSArray *enemies = FindEnemies(); id camera = [NSClassFromString(@"UnityEngine.Camera") performSelector:@selector(get_main)];
            if (!player || !enemies.count || !camera) { usleep(100000); continue; }
            
            CGSize screenSize = [[UIScreen mainScreen] bounds].size; CGPoint center = CGPointMake(screenSize.width/2, screenSize.height/2);
            id bestTarget = nil; float bestDist = 999999;
            
            for (id enemy in enemies) {
                @try {
                    if ([[enemy performSelector:@selector(get_Dead)] boolValue]) continue;
                    CGPoint screenPos = WorldToScreenPoint(camera, GetWorldPosition(enemy));
                    float dist = hypot(screenPos.x - center.x, screenPos.y - center.y);
                    if (dist <= fov && dist < bestDist) { bestDist = dist; bestTarget = enemy; }
                } @catch (...) { continue; }
            }
            if (bestTarget) AimAtEnemy(player, bestTarget, aimSpeed);
            usleep(16000);
        }
    }
    return NULL;
}

extern "C" {
    void AimBot_SetEnabled(bool enabled) { pthread_mutex_lock(&g_configMutex); g_config.enabled = enabled; pthread_mutex_unlock(&g_configMutex); LOGI("%s", enabled ? "Habilitado" : "Desabilitado"); }
    void AimBot_SetFOV(float fov) { pthread_mutex_lock(&g_configMutex); g_config.fov = fmaxf(10.0f, fminf(180.0f, fov)); pthread_mutex_unlock(&g_configMutex); }
    void AimBot_SetAimSpeed(float speed) { pthread_mutex_lock(&g_configMutex); g_config.aimSpeed = fmaxf(1.0f, fminf(10.0f, speed)); pthread_mutex_unlock(&g_configMutex); }
}

__attribute__((constructor)) static void Initialize() { LOGI("Inicializando..."); pthread_t thread; pthread_create(&thread, NULL, AimBotThread, NULL); pthread_detach(thread); }
__attribute__((destructor)) static void Cleanup() { LOGI("Finalizando..."); }