# ページ組版層（page）

`Sources/stone_engine/page/` は、stone_engine に足した「ページ組版層」です。EPUB リーダー SMSReader のために作りました。stone_engine と同じく MIT ライセンスです。

`STLabel` / `STTextView` は、1 つの文字列を 1 つの文字サイズで組みます。この層はその上で、書式の混ざった文章を段落ごとに行へ分け、決まった大きさのページに詰め、`CGContext` に描きます。電子書籍のリフロー表示に使うためのものです。

既存のファイル（`context` `font` `layout` `parse` `view`）には手を入れていません。そこから使っているのは次のものです。

- 縦組み用字形への置き換え（`STTextVerticalSubstitutionGlyphWithGlyph`、GSUB の vrt2 / vert）
- 約物の分類（`STPunctuation`）
- 禁則の文字表（`STKinsoku`）

## できること

- **組み方向**: 横組み（horizontal-tb）と縦組み（vertical-rl）。
- **書式の混在**: 1 行の中で、書体（明朝・ゴシック・任意のフォント）、大きさ、太字、斜体、色、字間が混ざってよい。足りない字形は、システムの代わりのフォントで補う。異体字セレクタ（IVS）付きの文字は CoreText で 1 字形にする。
- **ルビ**
  - モノルビ・グループルビ。親文字に画像（外字）を含んでもよい。
  - 長いルビは、前後のルビのないかなに、ルビ 1 字分まで掛ける。
  - 縦組みでは右、横組みでは上に置く。
- **圏点**: ゴマ・ドット・円・二重円・三角と、それぞれの白抜き。
- **縦中横**: 横に並べ、1 字の幅に収める。
- **文字の向き**
  - 縦組みでの正立と横転は、UAX #50 の主な範囲で決める。
  - `text-orientation` に当たる upright / sideways で、まとめて変えられる。
- **上付き・下付き**: ベースラインをずらす。
- **線**: 傍線・下線・打ち消し線。縦組みでは over が右、under が左。行にルビや圏点があれば、その外側に引く。
- **背景**: インライン（span）の背景色、ブロックの背景色。
- **画像**: 行の中の画像（外字）と、1 枚だけの画像のブロック（ページに収まるよう縮める・次のページへ送る）。
- **約物の詰め**
  - 「」「 や 。」 のように約物が続くときの半角詰め。
  - 行頭の始め括弧の詰め。
- **行の分け方**
  - 禁則（行頭・行末）。
  - 、。のぶら下げ。
  - 欧文は単語の間でだけ改行する。
  - ……・――・‥ は 2 字の間で分けない。
- **2倍ダーシ**: ―― ── —— は途切れないよう、つなげて描く。
- **ブロック**: 両端揃え（空白を先に、次に和字の間を広げる）、行頭・中央・行末揃え、最終行の揃え、字下げ（負の値でぶら下げ）、前後と左右の余白、行の高さ、改ページの前後、空行（`<br/>` だけの段落）。

## 使い方

```swift
import stone_engine

var body = STTextStyle()
body.size = 16
var ruby = body

var section = STSection(blocks: [
    STBlock(inlines: [
        .text("吾輩は", body),
        .ruby(base: [.text("猫", ruby)], ruby: "ねこ", style: ruby),
        .text("である。明治", body),
        .combined("38", body),          // 縦中横
        .text("年。", body),
    ], baseStyle: body),
], writingMode: .vertical)
section.numberBlocks()                  // 各ブロックの、章の文字列での位置

var settings = STReaderSettings()
settings.fontSize = 17
let typesetter = STTypesetter(settings: settings)       // スレッドごとに 1 つ（書体と字形を覚える）
let geometry = STPageGeometry(size: CGSize(width: 420, height: 600), top: 36, left: 28, bottom: 36, right: 28)
let pages = typesetter.paginate(section, geometry: geometry)

// 描く（ほかのスレッドからでもよい）
let image = STPageRenderer.image(pages[0], geometry: geometry, writingMode: .vertical,
                                 settings: settings, scale: 2, image: { id in nil })

// ページの上の文字の位置（選択・検索・リンク用）
let characters = pages[0].characters(geometry: geometry, writingMode: .vertical)
let rubies = pages[0].rubies
```

各ページは、章の文字列の中で自分がどこからどこまでかを持っています（`STPage.range`、UTF-16 単位）。そのため、文字の大きさを変えて組み直しても、同じ場所を指せます。

## ファイル

| ファイル | 内容 |
| --- | --- |
| `STPageModel.swift` | 文書の形（`STSection` `STBlock` `STInline`）、書式（`STTextStyle` `STBlockStyle`）、読み手の設定（`STReaderSettings`） |
| `STFontBook.swift` | 書体と字形のキャッシュ、縦組み用字形（上流の GSUB 読みを鍵の中で呼ぶ） |
| `STCharacterClass.swift` | 文字の性質（縦組みでの向き、約物、禁則、ぶら下げ、単語の文字）のキャッシュ |
| `STTypesetter.swift` | 行に分け、詰め、揃え、ページに詰める |
| `STPageRenderer.swift` | `CGContext` に描く |
| `STPageQueries.swift` | ページの上の文字・ルビ・ブロックの位置 |

## 速さ

20,000 字の章（『吾輩は猫である』の冒頭のくり返し）を、420×600pt のページに組む時間を測りました（iPad Air 11 インチのシミュレータ、デバッグビルド）。

| | 縦組み | 横組み |
| --- | --- | --- |
| ページ組版層 | 約 42ms（52 ページ） | 約 49ms |
| 参考: `STLabel.sizeThatFits` | 約 640ms | 約 610ms |

書体（`CTFont`）と字形を、1 回の組版の中でキャッシュしていることによる差です。

## 気をつけること

- `STTypesetter` はスレッドごとに 1 つ使ってください。組んだ `STPage` は変更しないので、複数のスレッドから同時に描けます。
- 上流の縦組み用字形の置き換えは、プロセス全体で 1 つの状態を持っています。この層では鍵（`NSLock`）の中で呼び、結果を自分でもキャッシュしています。
- UAX #50 は主な範囲だけを表にしています。ここにない文字は横転します。
- macOS 向けのビルドは、上流の `main` と同じく通りません（`STContext.swift` などが UIKit を使っているため）。この層そのものは CoreGraphics・CoreText・Foundation だけを使います。
