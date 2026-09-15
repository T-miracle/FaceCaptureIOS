# Uni-App 人脸拍照插件（iOS）

面向传统 Uni-App（Vue 2 / App-Plus）的 iOS 原生 Module。插件固定使用竖屏并隐藏状态栏；默认后置摄像头，可切换前后摄像头及双指缩放。正方形取景框宽度为屏幕宽度的 90%，在屏幕居中位置基础上向上移动取景框自身高度的 1/3，图 1 作为取景框顶层引导图；拍照按钮和镜头切换按钮位于底部，并保留约 1/8 屏幕高度的安全距离。

## 插件信息

- 插件 ID / Module 名称：`uni-face-capture`
- iOS Module 类：`UniFaceCaptureModule`
- Framework：`UniFaceCapture.framework`
- 最低 iOS：13.0

## GitHub Actions 构建

仓库需要配置：

- Secret `DCLOUD_SDK_REPO_TOKEN`：可读取 DCloud iOS SDK 私有 Release 的 Token。
- Variable `DCLOUD_IOS_SDK_REPOSITORY`：保存 SDK Release 的仓库，例如 `owner/FaceCaptureIOS`。
- Variable `DCLOUD_IOS_SDK_RELEASE_TAG`：Release 标签，例如 `dcloud-sdk-ios`。

对应 Release 必须包含 `SDK.zip`。工作流 `.github/workflows/build-ios-plugin.yml` 会定位 `DCUniModule.h`、构建真机静态 Framework，并上传 `UniFaceCapture-ios-plugin` Artifact。压缩包内是：

```text
artifact/
├── ios/UniFaceCapture.framework
└── package.json
```

把 `artifact` 目录重命名为 `uni-face-capture` 后放到 Uni-App 项目的 `nativeplugins/`。宿主必须配置 `NSCameraUsageDescription`，然后重新制作自定义基座或云打包。

```js
const faceCapture = uni.requireNativePlugin('uni-face-capture');

faceCapture.capture({}, result => {
    if (result.code === 0) {
        // result.path：正方形 JPEG 的本地绝对路径
        // result.uri：file:// URI
        // result.width / result.height：输出像素尺寸
    }
});
```

回调只执行一次：`code: 0` 表示成功，`code: 1` 表示用户取消，`code: -1` 表示权限、设备或处理失败。引导图只覆盖相机预览，不会合成到输出照片。
