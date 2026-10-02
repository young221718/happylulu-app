# HappyLulu 업데이트

1.5.1에 Sparkle 업데이트 확인 UI를 포함한다. **2026-10-02: 키체인 승인·서명 feed 게시·실제 설치 검증은 사용자 요청으로 보류했으므로 현재 자동 업데이트 서비스는 활성화되지 않았다.** 이번 1.5.1은 수동 설치 전용이다. 이후 자동 업데이트를 활성화한 앱이 배포되면 그 앱으로 다시 한 번 수동 교체해야 하며, 그다음 버전부터 앱 안에서 업데이트할 수 있다.

- 기본은 1시간마다 새 버전을 확인한다. 새 버전을 안내하고 사용자가 업데이트를 선택한 뒤 다운로드·설치·재실행한다. 동의 없이 다운로드하거나 설치하지 않는다.
- 별도 설정 창의 `업데이트`에서 자동 확인을 끄거나 `지금 업데이트 확인`을 사용할 수 있다.
- 출근 기록과 캘린더 연결 기록은 앱 bundle 밖에 있으므로 설치본 교체 시 유지된다.
- ZIP, 업데이트 목록과 릴리즈 노트의 Ed25519 서명을 검증한다. 서명되지 않은 목록과 변조된 파일은 허용하지 않는다.
- 업데이트 서명 비밀키는 제작자 맥의 키체인 `happylulu-updates` 계정에 저장한다. 앱에는 공개키만 들어간다.
- 소스는 비공개 저장소에서 관리하고, 업데이트 앱·목록·릴리즈 노트는 다운로드 사이트에서 제공한다. 제작자의 캘린더와 계정 정보를 배포 파일에 포함하지 않는다.

## 새 버전 만들기

`CFBundleVersion`을 이전 배포보다 큰 정수로 올리고 `CFBundleShortVersionString`과 `RELEASE-NOTES.md`를 갱신한다. 검증 후 다음 명령으로 로컬 파일을 만든다.

```sh
swift package resolve
bash scripts/package-release.sh
bash scripts/generate-update-feed.sh dist/releases/1.5.1-build9/HappyLulu-1.5.1-universal.zip
```

생성된 `dist/updates/`의 앱 ZIP, `appcast.xml`, 릴리즈 노트 파일을 다운로드 사이트의 `/updates/`에 게시한다. 실제 게시·공개 범위 변경은 별도 사용자 요청에 따라 수행한다. 서명 뒤 목록·노트를 편집하면 다시 서명해야 한다. 이전 업데이트 파일은 원본과 함께 보존한다.

업데이트 URL은 `Resources/Info.plist`의 `SUFeedURL`이다. URL이 접근 가능하고 올바른 서명 목록을 반환해야 실제 자동 업데이트가 작동한다. 앱 빌드와 서명 목록 생성만으로 서버 게시나 설치 성공을 주장하지 않는다.

## 확인 범위

앱 빌드, Framework 포함·서명, ZIP 서명·변조 거부, 업데이트 목록과 노트 서명을 각각 확인한다. 실제 업데이트는 이전 버전에서 최신 버전으로 내려받아 설치하고 재실행한 뒤 버전·출근 기록·캘린더 상태를 확인해야 한다. 회사 계정의 서버 캘린더 반영은 별도 시험이다.

공식 계약: [Sparkle 설정](https://sparkle-project.org/documentation/), [자동 확인·설치](https://sparkle-project.org/documentation/customization/), [업데이트 게시](https://sparkle-project.org/documentation/publishing/).
