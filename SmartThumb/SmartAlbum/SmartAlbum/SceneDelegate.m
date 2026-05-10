//
//  SceneDelegate.m
//  SmartAlbum
//
//  Created by zheng zhilin on 2026/5/10.
//

#import "SceneDelegate.h"
#import "ViewController.h"

@interface SceneDelegate ()

@end

@implementation SceneDelegate

/**
 * @brief 创建窗口并将首页包裹在导航控制器中。
 * @param scene 当前场景对象。
 * @param session 场景会话。
 * @param connectionOptions 连接配置。
 */
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    ViewController *viewController = [[ViewController alloc] init];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
    self.window.rootViewController = navigationController;
    [self.window makeKeyAndVisible];
}

/**
 * @brief 处理场景断开事件。
 * @param scene 当前场景对象。
 */
- (void)sceneDidDisconnect:(UIScene *)scene {
}

/**
 * @brief 处理场景进入活跃状态。
 * @param scene 当前场景对象。
 */
- (void)sceneDidBecomeActive:(UIScene *)scene {
}

/**
 * @brief 处理场景即将失活事件。
 * @param scene 当前场景对象。
 */
- (void)sceneWillResignActive:(UIScene *)scene {
}

/**
 * @brief 处理场景进入前台事件。
 * @param scene 当前场景对象。
 */
- (void)sceneWillEnterForeground:(UIScene *)scene {
}

/**
 * @brief 处理场景进入后台事件。
 * @param scene 当前场景对象。
 */
- (void)sceneDidEnterBackground:(UIScene *)scene {
}


@end
