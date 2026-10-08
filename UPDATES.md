# HappyLulu 업데이트

2026-10-07 사용자 요청으로 보류를 재개했습니다. Mac 1.5.9 build17부터 서명된 자동 업데이트를 활성화합니다. 1.5.6 이하 비활성 설치본은 최초 한 번 활성화 버전으로 교체해야 하며, 이후 앱이 업데이트를 처리합니다. 로컬 검증용 활성화 부트스트랩은 1.5.8 build16입니다.

- 기본은 시작 시와 1시간 주기로 새 버전을 확인하고 자동 다운로드·설치합니다. 기존에 저장된 사용자 설정은 존중하며, 설정의 업데이트에서 자동 확인·자동 설치를 각각 바꿀 수 있습니다.
- 자동 재시작은 앱 창이 닫히고 앱이 비활성이며 출근 저장·캘린더 동기화가 진행 중이 아닐 때 수행합니다. 준비된 업데이트는 정상 종료 시에도 설치됩니다. 설치 준비가 끝나면 해당 설치는 취소하지 않으며 재시작까지 설정 변경을 잠시 막습니다.
- 출근·캘린더 연결 기록은 앱 bundle 밖에 보관하므로 교체 시 유지됩니다. 실제 교체 전후 파일 해시/버전/실행 확인은 별도 검증합니다.
- 앱 ZIP, 업데이트 목록과 릴리즈 노트를 Ed25519로 서명하고 앱은 서명과 변조를 검증합니다. HTTPS feed 주소와 앱 공개키는 유지합니다.
- 비밀키는 제작자 맥의 키체인 `happylulu-updates`에 있으며 내보내거나 Git/사이트에 저장하지 않습니다. 키체인 승인창이 표시되면 사용자가 직접 승인합니다.
- Developer ID 서명·Apple 공증은 미완료입니다. 자동 업데이트 서명과는 별개이며 다른 맥의 보안 정책/설치 권한에 따라 확인이 필요할 수 있습니다. Intel 실기기는 보류입니다.

## 로컬 고정 코드 서명

빌드·패키징은 `scripts/sign-app.sh`를 공유합니다. 이 Mac의 로그인 키체인에 고정된 자체 서명 인증서를 보관하고, 공개 인증서와 지문 기록은 `~/Library/Application Support/HappyLulu/Signing/`에서 읽습니다. 개인 키를 Git이나 사이트에 넣지 않습니다. 시스템 전체의 인증서 신뢰 설정은 변경하지 않습니다.

다른 인증서를 지정할 때는 `HAPPY_LULU_SIGNING_IDENTITY`에 인증서 SHA-1 지문을 넣습니다. 지정한 인증서가 없거나 기록이 불일치하면 실패하며 ad-hoc으로 몰래 전환하지 않습니다. 로컬 기록도 지정값도 없는 개발 환경에서는 기존 ad-hoc 방식을 유지하고 출력에 명시합니다. 명시적인 ad-hoc 시험은 값 `-`를 사용합니다.

자체 서명은 Apple Developer ID·공증을 대신하지 않습니다. 같은 인증서와 앱 식별자가 업데이트 간 유지되는지 `bash scripts/check-code-signing.sh`로 검사합니다. 격리 시험 앱에서는 같은 인증서의 두 빌드 사이에 실제 Sparkle 다운로드·교체·자동 재실행을 확인했습니다. 실제 HappyLulu의 캘린더 권한 지속은 별도 실험 결과로 기록합니다. 외부 Mac의 Gatekeeper 설치 경험도 별도 검증 대상입니다.

## 새 버전 배포

`CFBundleVersion`을 기존보다 큰 정수로 올리고 버전·RELEASE-NOTES.md를 갱신합니다.

```sh
bash scripts/package-release.sh
bash scripts/generate-update-feed.sh dist/releases/1.5.10-build23/HappyLulu-1.5.10-universal.zip
swift run --build-system native AppUpdateChecks dist/releases/1.5.10-build23/HappyLulu.app dist/updates/appcast.xml
```

검증된 `dist/updates/`의 ZIP·appcast.xml·릴리즈 노트를 기존 사이트 `/updates/`에 게시합니다. 서명 후 파일을 수정하면 재서명해야 합니다. `/downloads/`에도 수동 설치 파일을 제공하며 이전 배포 파일은 보존합니다. 실제 게시·공개 범위 변경은 사용자 승인 범위 내에서 진행합니다.

검사 범위는 설정/서명·변조 거부, 서버 응답의 XML/Content-Type/해시, 이전 설치본에서 다운로드·교체·재실행 및 기록 보존입니다. 서버 게시만으로 실제 설치 성공을 주장하지 않습니다.

공식 계약: [Sparkle 설정](https://sparkle-project.org/documentation/), [자동 설치](https://sparkle-project.org/documentation/customization/), [유휴 시 설치](https://sparkle-project.org/documentation/api-reference/Protocols/SPUUpdaterDelegate.html), [배포](https://sparkle-project.org/documentation/publishing/).
