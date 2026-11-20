# ESCO Drive

中古車オークション（USS）の落札相場と、中古車サイトの小売相場を比べて、仕入れる価値のある車を探すシステムです。

> **ご利用にあたって**：あらかじめ決めた条件をもとに、仕入れの「候補」を探すための補助ツールです。利益・売却価格・落札できることを保証するものではありません。入札や仕入れの判断は、ご自身で行ってください。

## Windows

1. [ESCODriveSetup.exe をダウンロード](https://github.com/yukinakazawa1236/chuukosha-benri-dist/raw/main/ESCODriveSetup.exe)して、実行します。「Windowsによって保護されました」と出たら、「詳細情報」→「実行」を押します。
2. デスクトップの「ESCO Drive」をダブルクリックします。
3. 画面の上に、黄色い案内が出たら、「AIに渡す指示をコピー」を押して、Claude Code か Codex に貼ります。足りないものを、順に直してくれます。

## Mac（見る専用）

Macでは、USSの取得はできません（USBキーがMacに対応していないため）。USBキーのWindowsパソコンが取得した結果を、共有フォルダから取り込んで、見るために使います。

### いちばん簡単な方法：エージェントに頼む

Claude Code または Codex を開いて、次の文章を、**そのまま貼って**ください。

```text
このMacに、ESCO Drive（見る専用）をインストールしてください。

【やること】
1. ターミナルで、次のコマンドを実行する（管理者権限・sudoは使わない）：
   curl -fsSL https://raw.githubusercontent.com/yukinakazawa1236/chuukosha-benri-dist/main/install-mac.sh | bash
2. 終わったら、~/Applications/ESCO Drive.app ができていることを確認する。
3. アプリを起動する：open "$HOME/Applications/ESCO Drive.app"
4. 数秒待って、起動を確認する：curl -s http://127.0.0.1:3847/api/ping （{"ok":true...} と返ればOK）
5. 画面（アプリ風のウィンドウ）が開いたことを、私に伝える。

【うまくいかないとき】
- エラーが出たら、内容を私に見せて、原因を説明してから、直す。
- 起動しないときは、~/Library/Application Support/udgarage-auction/server.log を読んで、原因を調べる。
- 「開発元が未確認」と出たときは、私に「システム設定 → プライバシーとセキュリティ → このまま開く」を押すよう、伝える（あなたは、押さない）。

【守ること】
- パスワード、暗証番号、ログイン情報は、入力しない・求めない。
- sudo や管理者権限は使わない。
- 上のコマンドと、アプリの起動以外の、システムの設定変更や、ファイルの削除はしない。
- このMacは、見る専用です。USS（オークション）のサイトには、アクセスしない。

【終わったら】
次の2つを、私に伝える：「インストールできた」ことと、「次に私がやること：画面の『設定』→『データの共有』で、『フォルダを選ぶ…』を押して、共有フォルダ（Dropboxの中のフォルダ）を選ぶ」。
```

### 自分で行う方法（上級者向け）

ターミナルに、次の1行を貼って、実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/yukinakazawa1236/chuukosha-benri-dist/main/install-mac.sh | bash
```

### Macでの使い方

1. 「ESCO Drive」を、ダブルクリック（またはSpotlightで検索）して、開きます。
2. 「設定」→「データの共有」で、「共有を使う」にチェックを入れ、「フォルダを選ぶ…」を押して、Windowsのパソコンと同じ共有フォルダを選び、「保存して確認」を押します。
3. USBキーのパソコンが取得した最新の結果が、取り込まれます。

更新は、起動するたびに、自動で行われます。
