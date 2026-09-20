# RELAY: Jevを使った敵AIのデモ

Godotで作った潜入ゲームです。通常AIの警備・発見・追跡・無線連携を土台に、Jevが出来事の履歴から作戦を見直します。

**[Windows版をダウンロード](https://github.com/marvelousu/jev-stealth-demo/releases/latest)**

[約86秒の比較動画（YouTube）](https://youtu.be/qY8YDUMQMLI)

[解説記事：Jev をゲームの敵AIに組み込み、通常AIと動きを比べてみた](https://zenn.dev/marvelousu/articles/jev-game-ai-integration)

動画では潜入直後から発見され、煙幕で視界を切り、建物を回って逃げる様子を見せます。A・B・Cは同じ色です。両方式を同じスタート地点から最後まで見せます。開始前の静止画を右下へ移してから動き出し、図と実画面を同期させます。実演は0.75倍速、作戦が分かれる場面は0.5倍速。最後は同じ時刻・同じ範囲を拡大し、Aの移動と再発見の瞬間を左右で比較します。横型・音声なしです。

動画の目安：0:00 通常AI、0:34 通常AI＋Jev、1:04 拡大した左右比較。

**11秒の西の物音に対する、Aの行き先**に注目してください。通常AIはA・Bを援護付きの調査へ回します。同じAIにJevを足すと、通常の対応を始めたあと、Jevの返答を受けてAを東の警戒に残し、Bに西を見張らせました。どちらもCは保管庫を守ります。

この収録では、通常AIもCが侵入を止めました。Jev追加側は東に残ったAが保管庫の手前で再発見しています。通常の耐久で収録し、両方式ともプレイヤーは倒され、ケースに届いていません。作戦が分かれる4回目までは、両方式へ渡した観測入力が一致しています。この一例は、ゲームAI全般に対するJevの優位を示すものではありません。

## 遊ぶ

1. Releasesから`relay-windows-v0.1.5.zip`をダウンロードします。
2. ZIP全体を展開して、フォルダ内の`Play.cmd`を開きます。
3. 開始画面でEnterを押します。保管庫のケースを回収して南側の出口から脱出してください。

`Courtyard.cmd`では、動画と同じ操作の比較を開始します。**比較中も通常の耐久で、3発被弾すると失敗**します。`R`で自分で操作し、`F8`で再比較、`F9`で直進などの条件に切り替えられます。Jevへ実際に問い合わせるため、毎回同じ判断になるとは限りません。

Windows用です。キーボードとマウスで操作します。GodotやPythonのインストール、APIキーの入力は必要ありません。Jevを使うにはインターネット接続が必要です。接続できないときや共有の利用上限に達したときも、ルールAIでプレイを続けます。画面にはJevと代替ルールのどちらを使ったかを表示します。

配布物はGodot 4.6.3の実行環境とゲームのソースを同梱した試作版です。コード署名はしていません。

| 操作 | キー |
|---|---|
| 移動 / しゃがむ | WASD / Shift |
| 照準 / 射撃 | マウス / 左クリック |
| 単発の物音 / 繰り返す物音 | Q / F |
| 煙幕 | G |
| ケース回収・脱出 | 近くでE長押し |
| 敵の無線電源のON / OFF | 北西の設備の近くでE |
| やり直す / Jevとルールの切替 | R / M |
| 一時停止 | Esc |
| BGMのON / OFF | B または画面右下のボタン |

ケースはEを1.2秒、出口はEを2.5秒長押しします。被弾すると中断します。弾は6発、物音は3回、煙幕は2回です。敵の射撃を3発受けると倒れます。

北西の無線電源を切ると、離れた敵同士で目撃情報を共有できなくなります。近くの敵同士の連絡と、それぞれの視界・聴覚は残ります。

## 敵の判断を見る

- **F1**: 敵が知っている情報、選ばれた作戦、A・B・Cへの割り当てを確認します。
- **F10**: 判断パネル付きの比較を開始します。F1またはEscで再開します。
- F8は停止なしの比較、F9は比較条件の切替です。
- Hは判断履歴、F6は操作経路の記録、F7は再生です。

新マップの比較・記録再生は通常の耐久です。F6で操作を記録し、もう一度F6で止めてF7で再生します。回収・脱出のE長押しも記録し、再生中に倒されると失敗します。旧マップの観察・比較中だけ無敵を維持しています。

## Jevの担当

新マップでは、両方式とも通常AIが即座に対応します。Jev追加時は、ゲーム側の観測・記憶・目標・実行可能な作戦候補をJevへ送り、有効な返答が通常AIと異なるときに作戦を見直します。通信待ちや失敗で敵の対応を止めません。JevのChoiceと、条件に応じたNoulの結果から作戦を決めます。目撃情報はチーム内で共有し、最新の目撃地点に応じて回り込み担当の目標も更新します。役割の割り当て、移動、視界、射撃はゲーム側の処理で、ルール版とJev版の実行処理は共通です。

Jevが新しい作戦や移動座標を生成する構成ではありません。ルールAIも記憶・連携と同じ作戦を使います。同じ観測で同じ作戦を選ぶ場合もあり、この試作はJevの一般的な優位を示すものではありません。

## ソースから動かす

Godot **4.6.3**で`project.godot`をインポートします。新マップは`courtyard.tscn`を開いてF6で比較を開始し、Rで通常操作へ切り替えます。F5では旧マップが起動します。プロジェクト設定には共有デモ用サーバーのURLを入れてあります。APIキーはサーバーにだけ保存しています。

主なファイル:

| ファイル | 内容 |
|---|---|
| `main.gd` | ゲーム進行、非同期の問い合わせ、古い返答の破棄 |
| `tactics.gd` | 観測履歴、作戦から敵の役割・移動先への変換 |
| `mission.gd` | 回収、脱出、被弾などの任務ルール |
| `courtyard.gd` / `courtyard_replay.gd` | 新マップと通常耐久での比較 |
| `replay.gd` / `decision_gate.gd` | 旧マップの再生と判断適用時刻 |
| `explanation.gd` | 判断を確認するF1パネル |
| `backend/src/index.ts` | Cloudflare Worker、Jevの呼び出し、利用上限 |
| `backend/src/contract.ts` | リクエスト・返答の検証、作戦候補 |

## 自分のJev接続先を使う

`backend/README.md`に構成を記載しています。Node.jsとCloudflareアカウント、TypeSafeのAPIキーを用意します。

```sh
cd backend
npm ci
npm run check
# wrangler.jsoncのnameを自分のWorker名へ変更する
npx wrangler deploy
npx wrangler secret put TYPESAFE_API_KEY
```

キーは最後のコマンドの入力欄に入力し、ソースや`project.godot`には書きません。デプロイ後に`project.godot`の`[jev]`にある`service_url`を自分のWorkerのURLへ変更します。利用量に応じてTypeSafeとCloudflareの費用が発生します。自分の配布物を作るときも自分のサーバーを指定してください。

## 検証と配布用ZIPの作成

```sh
godot --headless --editor --import --quit --path .
godot --headless --path . --script res://verify_game.gd
godot --headless --path . --script res://qa/verify_explanation.gd
godot --headless --path . --script res://qa/verify_courtyard_replay.gd -- --play
python qa/run_audit_ui.py --godot C:\tools\Godot_v4.6.3-stable_win64.exe
python -m unittest -v test_distribution.py
```

Windows用Godot 4.6.3のGUI実行ファイルを指定して同梱版を作ります。

```powershell
python prepare_distribution.py --service-url https://YOUR-WORKER.workers.dev --godot C:\tools\Godot_v4.6.3-stable_win64.exe --output dist\relay-demo --zip
```

Godotのライセンスと第三者表記は`GODOT-LICENSE.txt`と`GODOT-COPYRIGHT.txt`に同梱しています。効果音は`make_audio.py`、BGMは`make_bgm.py`で生成したオリジナル音源です。BGMはゲームだけで再生し、設定は次回起動にも引き継ぎます。音源を作り直す場合のみNumPyとffmpegが必要です。

## ライセンス

このデモのコード・ドキュメント・オリジナル音源は[MITライセンス](LICENSE)で公開しています。著作権表示は `Copyright (c) 2026 marvelousu` です。Godot本体と同梱する第三者コンポーネントには、それぞれのライセンスが適用されます。
