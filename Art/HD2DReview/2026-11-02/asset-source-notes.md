Fireball flight/impact: user-confirmed built-in image_gen sheets; source prompts included in downloadable archive. Hero idle: user-confirmed v4, all240 source-timed frames retained for each hero, display atlas64x72. Training dummy: built-in image_gen static preview prop. No private account data, keys or signing caches included.
# 怪物素材补充

攻击施法补充：内置image_gen生成8张身体动作源图（普通4类，3精英各自独立，骨王独立），5张FX源图。最终90身体姿势+22FX帧，单独下载包monster-combat-source-assets.zip，不覆盖原行走包。普通战士和骨王仅发布宽格修正版，失败跨格图不打包。动作共用每角色的中立姿势比例；只登记支撑脚的整数纵向地面偏移，不用逐帧缩放或肢体变形。死亡使用已有角色原图闪白、淡出，叠加生成的六帧碎骨，0.68秒结束，属于简单运行时组合效果，不是额外20套AI死亡身体动画。网页命中/多弹只是预览，未接入正式游戏。

20种怪物由内置image_gen根据原V3怪物身份与已确认像素人物风格生成。可下载包 `dist/assets/monsters/monster-source-assets.zip` 包含5张原图与实际提示词、骨王无盾修正版、最终80个透明行走姿势、固定裁剪/公共锚点及复现处理脚本。最终运行图集为5张384×384 RGBA PNG，格子96×96。骨王以boss-corrected原图替换原elites-boss图最后一行。

动作范围仅行走：4姿势/种，150ms/帧，0.6秒循环。无插帧、无新画的攻击/死亡动画；受击红色由运行时source-atop叠色。HTML标注素材审阅样板，不能当成原生游戏集成或实机HD-2D场景。

