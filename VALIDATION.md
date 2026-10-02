# AfterSix 검증 기록

2026-09-28, 로컬 Mac에서 확인했습니다.

## 완료

- 환경: Apple Silicon, macOS 27.0 (26A428), Swift 6.4 Command Line Tools.
- `swift run --build-system native AfterSixChecks`: 18개 검사 통과.
- `bash scripts/build-app.sh`: Release 앱 생성, ad-hoc 서명 및 서명 검증 통과.
- `bash -n scripts/build-app.sh`, `plutil -lint Resources/Info.plist`, 소스 공백 검사 통과.
- 앱 의존성 확인: 시스템 프레임워크와 Swift 라이브러리만 사용. 빌드 디렉터리의 별도 동적 라이브러리에 의존하지 않음.
- `~/Applications/AfterSix.app`에 설치 및 실행.
- 실제 UI 확인: 출근 대기 화면, 수동 입력된 출근·퇴근 및 카운트다운 화면, 24시간제 표시, 근무 8시간·휴게 1시간, 자동 실행 켜짐.
- 앱 종료·업데이트·재실행 후 기존 수동 출근 기록 유지 확인. 테스트용 출근 시각을 실사용 저장 파일에 주입하지 않음.
- 설치 앱의 `--status`에서 `SMAppService.mainApp.status == 1` (`enabled`) 확인.
- 독립 GPT-6 Sol/xhigh 검토 수행. 지정 `reviewer` 역할의 고정 `biz/gpt-6-sol` 경로가 런타임에서 지원되지 않아, 사용 가능한 동일 Sol/xhigh 기본 역할로 읽기 전용 검토를 수행함. 자동 실행 최초 등록 실패 후 재시도 처리와 24시간 시각 표시를 수정한 뒤 재검토하여 차단 문제 없음 확인.

## 검사 범위

오전 6시 경계, 첫 해제만 기록, 새 날짜 전환, 근무+휴게 합산, 남은 분 올림 및 0 하한, 24시간 표시와 시간대, 수동 수정 보존, 미래·다른 날짜 거부, 수동 조기 출근, 쉬는 날 및 수동 복귀, 다음 날 자동 기록, 로컬 날짜, 일광절약시간의 경과시간 계산, 저장·복원 및 파일 권한, 출근 시각 임의 생성 방지, 손상 파일 원본 보존, 잘못된 근무 설정 거부, 미지원 스키마 거부.

## 미검증

- 실제 사용자의 화면 잠금·해제를 통해 `com.apple.screenIsUnlocked` 알림이 수신되는지.
- 로그아웃·로그인 후 자동 실행과 재부팅 첫 로그인 동작. 등록 상태 확인은 이 검증을 대신하지 않음.
- macOS 13~26 및 Intel 맥. 현재 산출물은 이 맥의 arm64용.
- App Store 배포, Developer ID 공증, 다른 맥 배포.

검증을 위해 사용자 맥을 강제로 잠그거나 재부팅하지 않았습니다. 실제 감지는 README의 잠금/해제 절차로 확인할 수 있습니다.

## 해결한 개발 환경 제약

XCTest가 설치되어 있지 않아 외부 설치 없이 실행하는 독립 검사 실행 파일을 사용했습니다. SDK 27의 `State` 매크로 플러그인 부재는 기존 SwiftUI 프로퍼티 래퍼를 타입 별칭으로 명시하여 해결했습니다. 기존 native 빌드 엔진의 향후 제거 경고는 남아 있으며, 현재 빌드와 실행은 완료했습니다.

## HappyLulu 1.1.0 이름·아이콘 변경

같은 날 사용자가 이름을 HappyLulu로 정하고 회사 동료용 아이콘 제작을 요청했습니다.

- 앱 이름, 실행 파일, 팝업 헤더, 접근성 이름, 앱 아이콘과 메뉴바 심볼을 변경했습니다.
- 근무시간 계산·알림 감지·저장 로직은 변경하지 않았습니다. 저장 경로와 번들 ID를 유지했습니다.
- 내장 이미지 생성 도구로 원본 PNG를 생성하고 RGBA 투명 외곽을 확인했습니다. 원본은 `Resources/HappyLuluIcon.png`에 보관합니다.
- `swift run --build-system native AfterSixChecks`: 18개 검사 통과.
- `bash scripts/build-app.sh`: `dist/HappyLulu.app` 빌드와 ad-hoc 서명 검증 통과.
- `bash -n scripts/build-app.sh`, `plutil -lint Resources/Info.plist` 통과.
- `~/Applications/HappyLulu.app`로 설치했습니다. 기존 설치 앱은 당시 프로젝트의 `.build/branding-before/AfterSix.app`에 보존했습니다.
- 기존 앱의 자동 실행 연결을 해제한 뒤 새 경로의 HappyLulu에서 다시 등록했습니다. 실제 UI와 설치 앱의 `--status`에서 켜짐/`enabled`를 확인했습니다. 실제 재로그인 시험은 수행하지 않았습니다.
- 실제 팝업에서 새 이름·웃는 시계 아이콘·소개 문구와 기존 출근 기록을 확인했습니다.
- 설치된 실행 파일·아이콘·Info.plist가 빌드 산출물과 바이트 단위로 일치합니다.
- 교체 전후 출근 기록 파일의 SHA-256이 일치하여 데이터가 수정되지 않았음을 확인했습니다.
- 새 범위는 외형·이름·패키징 변경이며, 앞선 독립 기능 검토를 새 버전 전체 검토로 표현하지 않습니다. 앞 절의 실제 잠금 해제 등 미검증 항목은 그대로 남아 있습니다.

## happylulu-app 저장소 이관

2026-09-28, Hive의 `dev/services/happylulu-app/develop/`에서 확인했습니다.

- 기존 프로젝트의 소스·검사·아이콘·문서 16개 파일을 복사하고 원본과 바이트 일치를 확인했습니다.
- 앱 동작 코드는 유지하고 개발 안내, 설치 방법, Git 제외 규칙을 정리했습니다.
- 새 위치의 `swift run --build-system native AfterSixChecks`: 18개 검사 통과.
- 새 위치의 `bash scripts/build-app.sh`: Release 빌드, 아이콘 패키징, ad-hoc 서명 검증 통과.
- `bash -n scripts/build-app.sh`, `plutil -lint Resources/Info.plist` 통과.
- Git 추적 대상은 소스·문서·원본 아이콘 17개 파일입니다. 1,125,213바이트의 원본 아이콘을 시각 확인했으며 앱 패키징 입력으로 포함합니다.
- 빌드 결과, 캐시, 이전 앱 백업, 개인 출퇴근 기록은 이관하거나 Git에 포함하지 않았습니다.
- 알려진 토큰·개인키 패턴 검사에서 후보 파일 내 일치 항목이 없었습니다. 이는 포괄적 보안 검토를 뜻하지 않습니다.
- 이관 빌드로 설치 앱을 교체하지 않았으며 실제 잠금·재로그인 등 기존 미검증 항목은 유지합니다.

## HappyLulu 1.2.0 마지막 금요일 조기 퇴근

2026-09-29, 로컬 Mac의 `worktrees/last-friday-early-leave/`에서 확인했습니다.
관련 요구사항은 GitHub 이슈 #1입니다.

- 기록된 출근 시간대의 양력 마지막 금요일에 근무+휴게 합계에서 120분을 빼고 출근 시각을 하한으로 적용합니다. 설정·출근 기록·저장 스키마는 변경하지 않습니다.
- 퇴근 예정, 메뉴바 카운트다운, 진행률이 같은 단축 시각을 사용합니다. 팝업과 설정에 적용 안내를 추가했습니다.
- `swift run --build-system native AfterSixChecks`: 기존 18개와 신규 6개를 포함한 24개 검사 통과.
- 신규 검사: 네 번째/다섯 번째 금요일, 평년/윤년 2월, 12월 말, 다른 요일·일반 금요일, 서울/LA/UTC 날짜 경계, 단축 후 카운트다운·진행률, 사용자 설정과 0시간 하한, 수동 출근 저장·복원.
- `bash scripts/build-app.sh`: Release 앱 빌드와 ad-hoc 서명 검증 통과. 진단 버전을 번들 정보에서 읽도록 변경한 뒤 빌드를 다시 확인했습니다.
- `bash -n scripts/build-app.sh`, `plutil -lint Resources/Info.plist`, `git diff --check` 통과.
- 빌드 앱의 읽기 전용 `--status`에서 `app=HappyLulu version=1.2.0` 확인.
- 기존 독립 Sol/xhigh 검토자가 이번 변경을 읽기 전용으로 검토했으며, 새로운 정확성·회귀 결함은 발견하지 않았습니다. 시간대 변경으로 날짜가 바뀌면 현재 로컬 날짜의 기록으로 전환하는 기존 동작은 README에 명시했습니다.
- 실제 마지막 금요일 UI 표시, 설치 앱 교체, 로그아웃·로그인·잠금 해제 시험은 이번 범위에서 수행하지 않았습니다. 기존 실제 기기 검증 제한은 유지합니다.
- Command Line Tools의 `--build-system native` 향후 제거 경고는 남아 있습니다.

## HappyLulu 1.5.1 기능 통합과 별도 설정 창

2026-10-02, Terra의 `app/mac/happylulu-app/worktrees/updates-1-5-1/`에서 확인했다.
GitHub 이슈 #3은 코드·업데이트 배포, #4는 실제 Mac 시험, #5는 설정 UI를 추적한다.

- 출퇴근 29개, 캘린더 코어 20개, 서비스 35개 검사 통과.
- 메뉴바에는 오늘 상태·출근 수정·반차·쉬는 날과 설정 열기만 두고, 지속 설정과 최근 기록을 별도 창으로 옮겼다.
- Universal arm64·x86_64 앱 빌드와 ad-hoc 서명 검증 통과. ZIP 추출 및 읽기 전용 DMG 안의 앱 파일을 원본과 SHA256으로 대조하고 서명을 재검증했다.
- Intel 링크에서 Swift compatibility packs의 x86_64 부재 경고가 있었다. 빌드는 완료됐지만 Intel 실기기 실행은 사용자 결정으로 후속이다.
- Swift native 빌드 엔진과 hdiutil create 옵션의 향후 제거 경고가 남아 있다.
- plist·패키징 스크립트 문법·diff 공백 확인 통과.
- UI fixture는 별도 임시 StateStore를 사용하며 사용자 출근 기록을 읽지 않고, 자동 실행 등록·캘린더·updater를 시작하지 않는다. 화면 배치 확인과 실제 앱의 창 전환·설정 값 변경은 다른 시험이다.

설치 앱을 강제 교체하거나 잠금·로그아웃·재부팅하지 않았다. 실제 계정 서버 왕복과 이전 앱 업데이트 설치, 권한 흐름은 #4에서 확인한다. 최종 업데이트 서명·Site 게시 및 독립 검토 결과는 완료 증거가 생긴 뒤 아래에 추가한다.

### 1.5.1 최종 검토 보완 (2026-10-02)

- 독립 검토의 충돌 해결 두 경로 수정: 미리보기·일시정지 및 최초 승인 snapshot 우회 쓰기 차단, 화면에 표시한 충돌 이후의 새 변경은 재확인 전 덮어쓰지 않음. 회귀 검사를 포함해 CalendarSyncServiceChecks 36개 통과.
- 캘린더 연결의 공개 서버 주소 선택·복사 버튼과 완료 피드백 추가. 구문 및 Universal 통합 컴파일 확인; 실제 사용자 화면의 복사 클릭은 사용자 시험에 남김.
- SUAllowsAutomaticUpdates=false로 Sparkle의 무동의 설치 opt-in도 차단. 기본 자동 확인은 false.
- 사용자가 키체인 승인·서명 feed 게시·자동 업데이트 활성화를 나중으로 보류함. HappyLuluUpdateServiceEnabled=false이며 업데이트 제어는 비활성. 서명 feed나 업데이트 파일은 게시하지 않음. 현재 수동 교체만 제공.
- AppUpdateChecks의 configuration-only 검사는 Sparkle 구성과 승인 정책을 검사하며 서명·변조 거부 검사를 명시적으로 제외한다. 서명 검사·실제 업데이트 설치 성공과 혼동하지 않는다.
- 최종 배포는 1.5.1 build9 Universal/ad-hoc이며 Developer ID와 Apple 공증, Intel 실기기, 실제 EventKit 서버 왕복·잠금 해제·로그인 시험은 미검증이다.
- 최종 보류 배포본의 ZIP 추출 앱 및 읽기 전용 DMG 앱이 원본 bundle의 모든 정규 파일 SHA256과 일치하고 각각 codesign --verify --deep --strict 통과. source Info.plist와 배포 bundle, source RELEASE-NOTES.md와 배포 노트의 byte 대조 통과.
- AppUpdateChecks --configuration-only 통과: 실제 Sparkle updater를 별도 defaults domain에서 시작하고 자동 확인을 켜도 자동 다운로드 opt-in이 거부됨 확인. 서명 검사는 SKIP으로 출력하며 실행하지 않음.
- 기존 출퇴근 29·Calendar core20 검사는 현재 기능 소스에서 통과했고, 최종 서비스 수정 뒤36검사 통과. Universal 최종 컴파일 통과. macOS의 deprecated native-build/hdiutil 및 Intel compatibility-library 경고는 빌드 실패가 아니며 Intel 실행 검증을 대체하지 않음.

## Mac 1.5.2 영어판 / Windows 1.0.0 (2026-10-02)

- Mac: 영어/한국어/시스템 언어 선택과 동적 날짜·기간·오류 표시 추가. native HappyLulu 빌드, 출퇴근 29검사·캘린더 서비스 36검사·plist lint 통과. 기존 미변경 Calendar core 20검사는 이전 기능 검증을 유지하며 이번 언어 변경으로 재실행하지 않음.
- Mac Universal 1.5.2 build10: arm64/x86_64 빌드 및 ad-hoc 서명 성공. `python3 scripts/verify-release.py dist/releases/1.5.2-build10`은 source plist/노트, ko/en 권한 리소스, SHA-256, ZIP·읽기 전용 DMG의 모든 파일/심볼릭 링크와 세 앱 서명을 대조해 통과. 기존 1.5.1 배포 파일은 보존.
- Mac UI: 별도 preview bundle ID와 임시 StateStore로 실제 SwiftUI 영문 패널 두 상태(364×470) 및 설정(620×700)을 렌더해 확인. 사용자 실제 기록·캘린더·로그인 등록·업데이트 시작은 사용하지 않음. 하단 내용은 스크롤 영역. OS 자체 오류/권한 팝업은 OS 언어를 따를 수 있음.
- Windows: 작업 경로에만 설치한 Microsoft .NET 10 SDK 10.0.401에서 코어 22검사, win-x64 교차 빌드 경고/오류0, self-contained/runtime-required publish 성공. ZIP은 HappyLulu.exe만 포함하며 무결성 검사 통과. 47,089,436바이트 런타임 포함본과 1,203,692바이트 런타임 별도본을 생성.
- Windows 작은 ZIP은 .NET 10 Desktop Runtime x64가 필요하며 Site 다운로드 옆에 명시. 기존 아이콘의 복사본은 원본과 동일한 SHA-256의 1,125,213바이트 소스 이미지로 검토함. 빌드 캐시·bin/obj·ZIP·PDB·개인 데이터는 Git에서 제외.
- 웹: 영어 `/en/` 랜딩과 전 페이지 언어 전환, 한국어/영어 Windows 설치 안내 추가. 8 HTML 경로·앵커·자산 및 신규/기존 배포 파일 해시, JS 구문 통과. 데스크톱·390px·768px 영어 내비 3개/수평 넘침 없음, 모바일 메뉴 선택 후 닫힘·다운로드 앵커 위치와 영어 마지막 금요일 예시 확인.

자동 업데이트 서명/활성화와 Intel 실기기는 사용자 요청대로 보류. 실제 Windows 트레이·언어 전환·잠금 해제·재로그인 자동 실행, Mac 기존 데이터 유지와 실제 잠금 해제/캘린더 서버 왕복은 미검증이며 사용자 시험이 필요하다. 독립 검토·GitHub CI·최종 Site 게시 결과는 실제 종료 결과 확인 후 별도 기록한다.
