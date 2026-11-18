# DroidLKM: sched_ext for android14-6.1

리눅스 6.12의 sched_ext를 커널 모듈 하나로 android14-6.1 GKI 커널에 얹는다. 커널은
다시 빌드하지 않고, 모듈은 `ksud insmod ... gki=1`로 올린다. 그 위에서 6.12용 BPF 스케줄러를
그대로 돌린다.

확인된 기기: Galaxy S24 Exynos (SM-S921N, 6.1.162-android14-11, Samsung EMS, KernelSU).

| 스케줄러 | 출처 | 상태 |
|---|---|---|
| scx_simple | 커널 트리 tools/sched_ext | 원본 그대로 동작 |
| scx_bpfland | scx v1.0.8 | 원본 그대로 동작 |
| scx_lavd | scx v1.0.8 | `contrib/scx61/scx_lavd-1.0.8.patch` 적용 후 동작 |

## 구조

- `src/scx61/upstream/`: linux-6.12.y의 `kernel/sched/ext.c` 등, 수정 없음 (`ORIGIN`에 해시).
- `scripts/gen-scx61.py`: upstream 파일을 6.1용 `ext-gen.c`, `cpumask-gen.c`로 변환한다.
  바꾸는 곳마다 이름과 기대 횟수가 붙어 있어서, upstream이 바뀌면 생성이 멈춘다.
- `src/scx61/`: 6.1에 없는 것을 채우는 글루.
  - `main.c`: 모듈 진입. idle 클래스 자리에 ext 클래스를 kprobe로 넣는다. 커널 메모리는 쓰지 않아서
    Samsung EL2 아래에서도 돈다.
  - `ext-glue.c`: 6.12 코어 쪽 동작(지연된 put_prev, enqueue/dequeue, 우선순위, 핫플러그,
    cpuperf, EMS 처리).
  - `btf.c`: 모듈 BTF를 vmlinux BTF에 붙이고 `sched_ext_ops` struct_ops 자리를 마련한다.
  - `kptr.c`, `cpumask-port.c`, `task-kfuncs.c`, `bpf-fixes.c`: 6.2 이후에 생긴 BPF 기능.
- `contrib/scx61/`: 스케줄러 빌드 도구, 6.1용 libbpf 패치, `scx-run`, 폰 테스트 스크립트.
- `tests/vm/`: QEMU arm64에서 GKI 커널로 돌리는 테스트.

## 빌드

모듈 (DDK 도커 이미지 사용):

```
python3 scripts/build-gki.py 6.1                          # GKI 헤더
python3 scripts/build-samsung.py 6.1 --module scx \
    --source <삼성 커널 소스> --config <기기 /proc/config.gz> \
    --kdir <작업 디렉터리> --out out/samsung/scx          # 삼성 기기
```

삼성 기기는 `build-samsung.py`로 빌드한다. 벤더 헤더가 있어야 BTF가 기기와 맞는다. `--kdir`에
기기의 `/sys/kernel/btf/vmlinux`를 `vmlinux`로 넣어 두면 모듈 BTF가 그걸 기준으로 만들어진다.

스케줄러:

```
contrib/scx61/build-upstream.sh <scx> <libbpf> <tools/sched_ext> scx_simple out/scx/upstream
SCX61_ARM64=<arm64 정적 라이브러리> SCX61_FOR_MAX=16 SCX61_INLINE=100000 \
    contrib/scx61/build-rust.sh <scx v1.0.8 체크아웃> scx_lavd out/scx/upstream
```

`contrib/scx61/Dockerfile`이 필요한 arm64 정적 라이브러리를 만든다. `build-rust.sh`는 cargo가
받은 libbpf-sys에 `libbpf-sys-1.4.6.patch`를, 스케줄러에 `NAME-*.patch`를 한 번씩 적용한다.
C 스케줄러용 libbpf에는 `libbpf-android14-6.1.patch`를 먼저 적용해 둔다.

VM 테스트 (QEMU arm64, KVM 없이 돈다):

```
python3 scripts/build-gki.py 6.1                 # out/gki/android14-6.1-scx/droidspaces_scx.ko
sh scripts/prepare-vm-kernel.sh                  # out/gki/android14-6.1/Image, DDK 이미지에서
docker build -t droidspaces-lkm-vm-cross:local -f tests/vm/Dockerfile.cross tests/vm
mkdir -p out/scx/upstream && cp <스케줄러 바이너리> out/scx/upstream/   # scx_simple 필수
tests/vm/run-scx.sh                              # DS_SCX_TRY=scx_lavd 로 하나만
```

스케줄러 바이너리는 위 빌드로 만들거나 폰용 묶음에 든 것을 그대로 쓴다. 에뮬레이션이라 몇
분 걸린다.

## 폰에서 돌리기

`contrib/scx61/phone/run.sh`와 모듈, `scx-run`, 스케줄러 바이너리를 한 디렉터리에 두고:

```
su -c sh /sdcard/Download/scx/run.sh
```

모듈을 올리고(이미 올라가 있으면 건너뜀) 스케줄러마다 10초씩 돌린다. 하나만 계속 돌리려면:

```
su -c 'cd /data/local/tmp/scx && ./scx-run ./scx_lavd'
su -c 'cat /sys/kernel/sched_ext/state; cat /sys/kernel/sched_ext/root/ops'
```

`scx-run`은 자기 마운트 네임스페이스에서 합쳐진 BTF를 `/sys/kernel/btf/vmlinux` 위에 덮고,
Android에 없는 `/var/run`을 만들어 준 뒤 스케줄러를 실행한다. 시스템의 다른 프로세스는 바뀐 걸
보지 못한다.

모듈은 내릴 수 없다(벤더 훅은 해제할 수 없다). 모듈을 바꾸려면 재부팅해야 하고, 스케줄러만
바꿀 때는 필요 없다.

## 6.12와 다른 점

- `sched_setscheduler(SCHED_EXT)`는 없다. 6.1 코어가 정책 7을 모른다. 스케줄러는 전체 전환
  모드로만 돈다.
- `bpf_for()`, `bpf_repeat()`, `bpf_for_each()`는 6.4의 반복자 대신 횟수가 정해진 루프다
  (`contrib/scx61/compat.bpf.h`). 상수가 아닌 범위는 `SCX61_FOR_MAX`회까지만 돈다.
- 6.1 검증기는 반복을 한 바퀴씩 전부 검사해서, 큰 스케줄러는 명령 100만 개나 분기 8192개 한도에
  걸린다. scx_lavd 패치는 그래서 들어갔다: `pick_any_bit()`을 루프 없는 계산으로 바꾸고(결과는
  같다), 컴퓨트 도메인 상한을 8로, CPU 상한을 64로 줄이고, 태스크 이름을 스택에 복사해서 비교한다.
  상한을 넘는 기기에서는 lavd가 시작할 때 거부한다.
- 참조 kptr을 맵에서 읽을 때 6.1은 untrusted로 표시한다. 모듈은 그 표시를 지운다. 검증기의
  검사 하나를 6.2 쪽으로 푼 것이다.
- 6.1에서 task storage 조회는 같은 CPU에서 다른 storage 작업이 진행 중이면 실패한다. 모듈은
  6.2처럼, BPF 콜백이 도는 동안 그 CPU의 표시를 비켜 둔다.
- cpuperf 목표는 cpufreq 정책별 최소 주파수 요청으로 바뀐다. 20ms마다, 1/16 단위로만 다시
  계산한다. 엑시노스에서는 요청마다 전력 관리 펌웨어로 메시지가 가서, 제한이 없으면 펌웨어가
  응답을 멈추고 기기가 리셋된다.
- fentry/fexit 프로그램은 6.1 arm64에 없어서 libbpf 패치가 건너뛴다. scx_lavd의 futex 추적이
  그래서 꺼져 있다.

## 알려진 문제

- BPF 검증·로드 중에 자주 불리는 커널 함수(`bpf_task_storage_get`, `push_stack`)에 kprobe를
  추가하면, Galaxy S24에서 struct_ops 트램폴린이 실행 불가 메모리로 남아 패닉이 났다. 원인은
  모른다. 모듈은 그런 kprobe를 쓰지 않는다.
- 맵 순회 콜백(`bpf_for_each_map_elem`)은 아직 kCFI 대응이 안 됐다.
- 장시간 안정성은 아직 확인하지 않았다. 지금까지는 몇 분 단위 사용만 확인했다.

## 라이선스

GPL-2.0. `vendor/kallrecon`은 github.com/Dere3046/KallRecon에서 가져왔고, 역시 GPL-2.0이다
(`vendor/kallrecon/ORIGIN`).
