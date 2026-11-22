# FjChargeLimit — 富士通 LIFEBOOK U9311/F の充電上限ツール(非公式)

富士通 LIFEBOOK U9311/F には、Windows で充電上限を設定する公式ツールがありません。
`FjChargeLimit.ps1` は、PC 本体の EC(エンベデッドコントローラー)にある充電上限を、Windows から確認・設定する PowerShell スクリプトです。

上限を 80% などにしておくと、AC アダプターを差したままでも残量が上限以上なら充電されず、PC はアダプターの電源で動きます。

> [!WARNING]
> 富士通(富士通クライアントコンピューティング)とは関係のない、非公式のツールです。動作を確かめたのは下記の 1 台だけです。ご利用は自己責任でお願いします。

## 動作を確かめた環境

| 項目 | 内容 |
|---|---|
| 機種 | LIFEBOOK U9311/F(型名 FMVU34021) |
| BIOS | 2.54 |
| OS | Windows 11 Pro 26H2(ビルド 26300) |
| ドライバー | Fujitsu FUJ02E3 Device Driver 4.6.1.0 |

管理者権限は要りません(管理者として実行していない PowerShell で動きました)。

## 必要なもの

- Fujitsu FUJ02E3 Device Driver(`fuj02e3-utility.dll` を含む)。富士通のドライバーとして入っていれば、追加のインストールは要りません。
- Windows PowerShell 5.1

## 使い方

```powershell
# 今の上限と電池の状態を表示する(設定は変えない)
powershell -NoProfile -ExecutionPolicy Bypass -File .\FjChargeLimit.ps1

# 上限を 80% にする(50〜100 の範囲で指定)
powershell -NoProfile -ExecutionPolicy Bypass -File .\FjChargeLimit.ps1 -Set 80

# 上限を外す(100% に戻す)
powershell -NoProfile -ExecutionPolicy Bypass -File .\FjChargeLimit.ps1 -Set 100
```

表示の例:

```
Charge limit: 80%
Battery: 89%  AC=True  Charging=False  Discharging=False  ChargeRate=0mW  DischargeRate=0mW
```

## 確かめた動き

- 充電中に上限を残量より低くすると、すぐに充電が止まる。PC はアダプターの電源で動き続け、バッテリーは放電しない。
- 残量が上限を少し下回っただけ(上限 80%・残量 79%)では、充電は再開しない。上限より 11% 低い(上限 90%・残量 79%)と充電が始まり、上限ちょうどで止まる。
  - 富士通の公式説明でも、80% 充電モードは「69% 以下で充電」、通常(100%)は「89% 以下から充電開始」とされていて、この結果と合っています。
- 設定は EC に保存されるので、再起動しても残る。Windows のどのアカウントでも同じ設定になる。
- まだ確かめていないこと:BIOS を更新したあと、バッテリーが完全に空になったあとも設定が残るか。

## 仕組み

ACPI の `\_SB.FEXT.FUNC(0x1006, 0x21, cmd, 0)`(DSDT の `S006` にある、EC のバッテリー用メールボックス)を、FUJ02E3 ドライバーに付属する `fuj02e3-utility.dll` の `CallFuncMethod` 経由で呼び出しています。

| cmd | 意味 |
|---|---|
| `0x21` | 今の上限(%)を読む |
| `上限 × 0x100 + 0x20` | 上限を設定する(EC が受け付けない値には 0 を返す) |

Linux カーネルの fujitsu-laptop ドライバー(`charge_control_end_threshold`)と同じ方式です。
この機種の BIOS は、富士通の新しい充電上限 API(FUNC 0x2002)や、ACPI 標準の `_BMC` には対応していません。

## うまくいかないとき

- **アダプターを差し直しても認識されない:** 動作を確かめた環境では、アダプター側の問題でした(上限 100% でも起きました)。アダプターをコンセント側で抜き差しすると直りました。
- **`fuj02e3-utility.dll not found` と出る:** Fujitsu FUJ02E3 Device Driver が入っていません。富士通のサポートページから入手してください。
- **`EC returned error 0x80000000` と出る:** その機種の BIOS が、この機能に対応していません。

## 参考

- [バッテリーの充電モードを変更する方法を教えてください。(富士通 Q&A)](https://www.fmworld.net/cs/azbyclub/qanavi/jsp/qacontents.jsp?PID=7307-4244)
- [バッテリーが充電されません。(富士通 Q&A)](https://www.fmworld.net/cs/azbyclub/qanavi/jsp/qacontents.jsp?PID=8504-6582)

## ライセンス

[MIT](LICENSE)

---

## English

An unofficial PowerShell script that reads and sets the battery charge limit (charge end threshold, 50–100%) stored in the embedded controller of a **Fujitsu LIFEBOOK U9311/F (FMVU34021)** on Windows. Fujitsu provides no official charge-limit tool for this model.

- Tested on one machine only: BIOS 2.54, Windows 11 Pro 26H2, Fujitsu FUJ02E3 Device Driver 4.6.1.0. No administrator rights needed.
- It calls `\_SB.FEXT.FUNC(0x1006, 0x21, cmd, 0)` (the EC battery mailbox in `S006`) through `CallFuncMethod`, exported by `fuj02e3-utility.dll`. `cmd = 0x21` reads the limit; `cmd = pct * 0x100 + 0x20` sets it. This is the same mechanism as the Linux `fujitsu-laptop` driver (`charge_control_end_threshold`).
- Observed behaviour: charging stops at the limit while the PC keeps running on AC power. Charging resumes only after the level drops about 11 points below the limit (Fujitsu documents 69% for its 80% mode). The setting survives reboots and applies to every Windows account.
- Usage: `powershell -NoProfile -ExecutionPolicy Bypass -File .\FjChargeLimit.ps1 [-Set 50..100]`
- Use at your own risk. Not affiliated with Fujitsu or Fujitsu Client Computing.
