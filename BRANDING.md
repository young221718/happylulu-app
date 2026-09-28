# HappyLulu 브랜드와 아이콘

- 이름: **HappyLulu**. 사용자가 룰루랩의 사내 유틸리티 이름으로 선택했습니다.
- 소개 문구: **우리의 하루를 더 즐겁게.**
- 아이콘: 청록·민트 바탕, 크림색 웃는 얼굴, 오른쪽 위 작은 시계 포인트.
- 회사의 공식 CI 파일을 복제한 것이 아닌 이 앱을 위해 새로 만든 심볼입니다.
- 앱 아이콘 원본: [Resources/HappyLuluIcon.png](Resources/HappyLuluIcon.png), 1254×1254 RGBA, 투명 외곽.
- macOS 아이콘: `scripts/make-icon.swift`가 원본을 각 macOS 아이콘 크기로 리샘플링하고 `iconutil`이 `.icns`로 패키징합니다.
- 메뉴바 심볼: `Sources/AfterSix/LuluBrand.swift`의 간략한 벡터 얼굴. 18pt 템플릿 이미지로 시스템 밝고 어두운 메뉴바에 적응합니다.

## 생성 기록

2026-09-28, 내장 `image_gen` 도구로 단일 아이콘을 생성했습니다. 외곽 투명 옵션을 사용했고 원본의 알파 채널을 유지합니다. API/CLI 대체 경로는 사용하지 않았습니다.

아래 프롬프트를 사용했습니다.

```text
Use case: logo-brand. Create one final production-ready macOS app icon for a small friendly workplace companion app named HappyLulu, made for colleagues at lululab. Current feature remembers arrival time and shows time left in the workday; future features will be practical employee utilities. Primary mark: an original cheerful smiling clock face, with two small rounded pill-shaped eyes and a clean upward smile. Make the clock idea very subtle: a short offset tick or small top/right notch integrated into the face's circular contour, no numerals or complicated clock hands. Warm, friendly, professionally restrained, recognizable at tiny sizes. A single centered rounded-square macOS icon tile, near-front orthographic view, very softly dimensional and tactile but with crisp simple geometric silhouettes. Palette inspired by the existing app: deep teal/mint tile and a warm ivory face with deep teal facial features. The smile is the hero. Center the tile with approximately 7% transparent margin on each edge in a square 1024x1024 canvas. Real transparency outside the rounded tile. No text, no letters, no wordmark, no company logo, no watermark, no extra objects, no mockup, no multi-option sheet. No alarm bells, no briefcase, no running person. Deliver a single standalone icon asset, not a presentation.
```

출력 크기는 도구가 반환한 1254×1254를 보존했으며, 앱 패키징 시 16~1024픽셀 변형을 만듭니다. 원본 디자인의 재생성·수정은 이미지 생성 도구로, 메뉴바 벡터 및 패키징은 네이티브 코드로 관리합니다.
