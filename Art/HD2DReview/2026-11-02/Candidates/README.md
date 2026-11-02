# 未启用的新美术候选 · 2026-11-02

使用内置image_gen生成，完整提示词见prompts.json。四项土系为每项16格原画草稿，尚未做生产拆帧/固定锚点/命中时刻登记及1—5级组合验收，不能把它们当作已确认的稳定动画。当前原生对应四项仍使用上一版素材。

- earth-spikes-draft-v1.png：地脉穿刺。
- stone-fist-draft-v1.png：岩拳升龙。
- boulder-draft-v1.png：巨岩砸地。
- quicksand-draft-v1.png：流沙地涡。
- earth-candidates-alpha-review.jpg：按实际alpha合成的深浅底审阅，不是透明生产图；原PNG没有改像素或alpha。部分查看器会把低于1%的alpha底噪RGB显示成红色，不能仅看未合成预览判定实际轮廓。
- grassland-lighting-study-v1.png：有厚度的围墙/前后景、暖阳与冷色阴影方案，是场景审阅图，未作为平面背景贴进游戏，也未据此声称已实现3D空间与光照。

场景PNG超过2MiB，按原格式分为1MiB无损分片，纳入source-parts.json；运行Tools/HD2DMaterialReview/restore_sources.py还原，原字节哈希保留。其余PNG直接保存在Git。所有尺寸/哈希见validation-drafts.json。母稿均保留，未经用户确认不覆盖上午与下午确认素材。
