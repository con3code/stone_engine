# ページ組版層（page）

`Sources/stone_engine/page/` は、stone_engine に足した「ページ組版層」です。EPUB リーダー SMSReader のために作りました。stone_engine と同じく MIT ライセンスです。

`STLabel` / `STTextView` は、1 つの文字列を 1 つの文字サイズで組みます。この層はその上で、書式の混ざった文章を段落ごとに行へ分け、箱・表・段組・回り込みとともに決まった大きさのページに詰め、`CGContext` に描きます。電子書籍のリフロー表示に使うためのものです（SMSReader はこれで次世代パブリッシング研究会『EPUBリーダー表示テスト』のほとんどの項目を表示します）。

既存のファイル（`context` `font` `layout` `parse` `view`）には、禁則の文字表のほかは手を入れていません。そこから使っているのは次のものです。

- 縦組み用字形への置き換え（`STTextVerticalSubstitutionGlyphWithGlyph`、GSUB の vrt2 / vert）
- 約物の分類（`STPunctuation`）
- 禁則の文字表（`STKinsoku`）。行頭禁則の表は、JLREQ の行頭禁則の文字クラスをすべて含むように足した（全角の「！」「，」「．」「：」「；」、「・」「･」、「ゝ」「ゞ」「ー」、「‐」「–」「〜」「゠」、「}」「⦆」「｣」。`STLabel` / `STTextView` の行分けにも効く）。JS 版（stone_engine_js の layout.ts）の同じ修正に合わせた

## できること

- **組み方向**: 横組み（horizontal-tb）と縦組み（vertical-rl）。
- **書式の混在**: 1 行の中で、書体（明朝・ゴシック・任意のフォント）、大きさ、太字、斜体、色、字間が混ざってよい。足りない字形は、システムの代わりのフォントで補う。異体字セレクタ（IVS）付きの文字は CoreText で 1 字形にする。
- **ルビ**
  - モノルビ・グループルビ。親文字に画像（外字）を含んでもよい。
  - 長いルビは、前後のルビのないかなに、ルビ 1 字分まで掛ける。漢字には掛けない。片側だけがかななら、その側に多く掛ける（`STRuby.shift` でルビを親文字の中央からずらす。JLREQ 3.3.8）。行頭・行末では、前後の行のかなには掛けられないので、反対側のかなに多く掛け、それでも足りない分は親文字の前（行頭）か後ろ（行末）を空ける（`STTypesetter.rubyLead`・`rubyTail`）。行に入らなければ、その語を次の行へ送る。
  - 熟語ルビ（JLREQ 3.3.7）: 続くモノルビの書式に同じ `STTextStyle.rubyJukugo` を付けると 1 つの熟語として組む。ルビが親文字より長いときは、同じ熟語の隣の親文字の上まで続けて置き、親文字の間は空けない。熟語全体でルビのほうが長いときだけ、外側のかなに掛け、残りを親文字の間に 1:2:1 で配る。熟語の中の親文字の間では行を分けられる。
  - 縦組みでは右、横組みでは上に置く。
  - ルビや圏点は行間（前の行の側の半分も含む）に置き、行間に収まるかぎり行送りを変えない（JLREQ 4.5.1）。収まらないほど行間が狭いときだけ、その行を広げる。
  - グループルビは 2 行に分けない（JLREQ 3.3.6）。
- **圏点**: ゴマ・ドット・円・二重円・三角と、それぞれの白抜き。印の字形の黒い部分の中心を、字の中心にそろえる。
- **縦中横**: 横に並べ、1 字の幅に収める。2〜4 字は、書体にあれば半角・三分・四分の字形（hwid・twid・qwid）を使い、なければ縮める。圏点は縦中横に 1 つ付ける。
- **文字の向き**
  - 縦組みでの正立と横転は、UAX #50 の主な範囲で決める。
  - `text-orientation` に当たる upright / sideways で、まとめて変えられる。
  - 引用符 “ ” ‘ ’（UAX #50 は Unicode 18 から Tr）は、和文に付くとき（始めは後ろ、終わりは前の字が和文のとき）全角の縦組み用字形（fwid と vert。〝〟の形）で正立させ、欧文に付くときと書体に縦組み用字形がないときは横転させる。
- **上付き・下付き**: ベースラインをずらす。
- **線**: 傍線・下線・打ち消し線。縦組みでは over が右、under が左。行にルビや圏点があれば、その外側に引く。
- **背景**: インライン（span）の背景色、ブロックの背景色。
- **画像**: 行の中の画像（外字）と、1 枚だけの画像のブロック（ページに収まるよう縮める・次のページへ送る）。行の中の不透過な画像（JPEG の外字など、アルファのないもの）は、紙の色が明るい（明るさ 0.5 以上）とき乗算で描き、白い所に地色を出す。書式に mix-blend-mode があればそれを使う。
- **約物の詰め**
  - 約物が続くときの半角詰め（JLREQ 3.1.4、CSS の trim-adjacent）。終わり括弧・句読点の後ろは、次が終わり括弧か中点類のときだけ詰め、始め括弧の前は二分を残す（」「 、「 。「 ）（ は 1.5em。」」 。」 「「 も 1.5em）。全角の ，．も句読点として扱う。
  - 行頭の始め括弧の詰め。段落の頭と強制改行の後ろでは詰めない（space-first）。
- **行の分け方**
  - 禁則（行頭・行末）。行頭禁則は、line-break の指定がないときと strict で表のすべて、normal では小書きの仮名・「ー」・「‐」「–」「〜」「゠」を、loose ではさらに繰り返し記号（々〻ゝゞヽヾ）と中点類（・･：；）を行頭に置いてよい（CSS Text の規定どおり）。
  - 、。のぶら下げ。
  - 欧文は単語の間でだけ改行する。
  - ……・――・‥ は 2 字の間で分けない。くの字点の〳〵・〴〵も分けない。
  - ASCII の " ' は、空白・行頭・始め括弧の後ろなら始め、そうでなければ終わりとして禁則にかける（UAX #14 の QU）。
  - 分割禁止（JLREQ 3.1.10）: 数字の中の . , :（3.14・1,000・12:30）、数字の前の通貨記号（¥1000・$25）、文字の間の .（U.S.A.・example.com）、横組みの全角数字とその記号（２０２６・５０％・￥１００）では改行しない。ノーブレークスペース（U+00A0・U+202F・U+2007）とワードジョイナー（U+2060・U+FEFF）の前後でも改行しない。合印（注・図の参照の記号）は `STTextStyle.keepsWithPrevious` を付けると、前の字との間でも、合印の中でも改行しない（行頭に来ない）。
  - 追い込みを追い出しより先に試す（JLREQ 3.8.2）。禁則や分離禁止で行を終えられない字が行からあふれたら、その行の約物と空白を詰めて入るかを見て、入るなら入れる。詰める順は JLREQ 3.8.3 にならい、欧文間の空白（四分まで）→ 中点類の前後の四分 → 括弧類・読点の二分（句点は行末だけ）→ 和欧間（八分まで）。
  - 行を伸ばす順は JLREQ 3.8.4 にならい、欧文間の空白（二分まで）→ 和欧間（二分まで）→ 和字間に均等。始め括弧の後ろ、終わり括弧・句読点の前、分離禁止の字の間、ルビの親文字の間、欧文の単語の中は空けない（JLREQ 3.1.11）。
- **2倍ダーシ**: ―― ── —— は途切れないよう、つなげて描く。
- **ブロック**: 両端揃え（伸ばす順は上の「行の分け方」）、行頭・中央・行末揃え、最終行の揃え、字下げ（負の値でぶら下げ）、リストの記号を行の外に出す（`outsideMarker`・`markerEdge`。list-style-position: outside）、前後と左右の余白（CSS どおりに相殺し、ページの頭では捨てる）、行の高さ、改ページの前後、空行（`<br/>` だけの段落）、孤立行（orphans・widows）、1 行目だけの書式（::first-line）。次のブロックと離さない（`keepsWithNext`。表のキャプションや break-after: avoid のブロックを、見出しと同じくページの末尾に残さない）。回り込みの下へ送る（`clearsStart`・`clearsEnd`。clear。ブロックの余白は回り込みの下までの空きに含める）。
- **箱**（`STBox`、ブロックの列の中の `boxStart` と `boxEnd` で囲む）: 罫（実線・破線・点線・二重線ほか）、角丸、背景色、背景画像（並べ方・大きさ・位置）、線形・放射・繰り返しのグラデーション、影（外・内）、輪郭線、border-image（9 分割）、幅と高さ（固定・最小・最大）、中身から決まる幅（min-content・max-content・fit-content。`intrinsicInline`、組む前に `resolvingIntrinsicSizes` で測る）、中身を中央に寄せる、回転・拡大・移動（中心は指定できる）、合成モード（mix-blend-mode・background-blend-mode）、中身の切り抜き、ページ・段で分かれたときの辺（slice・clone）、改ページ・改段の前後、分割しない（break-inside: avoid）。罫と padding と 1 行目が入らないページ・段の末尾では始めない。
  - 2 辺だけの罫（border-style: solid none none solid など）の角丸は、辺ごとに接する角の丸みを半分ずつ受け持ち、隣の辺とつないで曲線にする。四角い背景は画素に揃えて塗る。
  - ページをまたぐ箱の背景（box-decoration-break: slice）は、箱全体の矩形に敷いて各ページの切れ端の形で切り取る（`STPlacedBox.sliceBefore`・`sliceAfter` が、その切れ端の前と後ろにある箱の長さ）。clone は切れ端ごと。
  - ページの残りいっぱいの箱（`fillsPage`。電書協の天地中央・下寄せ）は、置かれたページの残りを最小の大きさにし、中身を中央に（`contentAtEnd` なら終わりに）寄せる。
- **行の中の箱**（`STInlineBox`）: inline 要素の padding・罫・地色を、行ごとにその文字の範囲で描く（ルビまで含めて囲める）。行方向の余白（`marginStart`・`marginEnd`。縦組みでは margin-top・margin-bottom）は、負の値も含め、要素の最初の文字の前と最後の文字の後に取る。背景と罫は余白の内側に描き、文字の位置（`characters`）も余白を除いて返す。行と直交する向きの余白は行に影響しない（CSS 2 §10.6.1）。
- **表**（`STTable`）: 列の長さは指定（%・pt）と中身から、行の高さはいちばん高いセルに。行の間で改ページする。縦組みでも組める。複数の行にまたがるセル（`rowSpan`、HTML の rowspan）は、下の行でその列を空けて次のセルを右の列に置き、またがる行の合計より高ければ最後の行を高くする。またがる行は同じページに置く。セルの中の画像も組む（幅を決めるときに数え、セルとページに収まるよう形を保って縮める）。`maxLength`（max-width、縦組みでは max-height）を超えない。
- **回り込み**（`.float`）: 画像を行の先頭か末尾に寄せ、横の行を短くする。浮動するブロック（`STFlow.floatsAtEnd`）も同じように置く。
- **段組**（`STColumns`）: 段数か段の幅、段間と段間罫、balance（段の長さをそろえる）と auto、段抜き。段の中の改段。このページで割れるが次のページなら収まる段組は、直前の見出しといっしょに次のページへ送る。
- **書字方向の混在**（`STFlow`）: 横組みのページの中の縦組みのブロック（扉など）、その逆。
  - 中身は罫と padding の内側に組み（`insets`。box-sizing: border-box なら枠の外寸）、罫・背景・角丸・影・輪郭線・背景画像を通常の箱と同じく描く（`box`。ページの `STPlacedBox` として置き、`STPlacedFlow.placedBox` が指す）。箱の回転・拡大・移動・合成モードは中身にもかける。
  - float があれば、画像と同じく行の端に置き、脇の行を短くする（Apple Books と同じ組み方）。left・right は行頭・行末（縦組みでは上・下）。余白（`margins`。`STEdges` は before・after・start・end の 4 辺）を空け、脇の行はその外側で止まる。脇に 4 字分も残らないときはページの幅で置く。
  - 同じ組み方向の flow は浮動のときだけ作る。1 ページに収まらないときと脇に 4 字分も残らないときは、中のブロックを本文としてそのまま組む。幅が中身から決まる flow は、いちばん長い行の長さで組み直す。
- **書体**: 本の書体（`STFontFamily.faces`。太字・斜体・unicode-range で face を選ぶ）、等幅、欧文の本物のイタリック体、OpenType の機能（kern・liga・jp90 ほか）。欧文は単語ごとに CoreText で組み、カーニングと合字を効かせる。
- **約物と行分け**: 行頭・行末・隣接の約物の詰め（text-spacing の space-first・trim-start・allow-end ほか）、和欧間・和数間の四分アキ、word-break（keep-all・break-all）、line-break（loose・normal・strict・anywhere）、長い単語を分けるか（overflow-wrap）、欧文のハイフネーション、行頭の始め括弧と行末の句読点のぶら下げ。
- **ルビ（追加）**: 下側のルビ、両側ルビ、ルビの揃え（start・center・space-between・space-around）、行より長いグループルビの行分け（行に収まらないときだけ、親文字の字数の割合で読みを分ける）、圏点の位置（over・under）と約物には付けないこと、ルビの外側の圏点。
- **線（追加）**: 線の種類（実線・二重線・点線・破線・波線）と色、縦組みの傍線の左右（text-underline-position）、文字ごとの位置。
- **言語と方向**（`STBidi.swift`）
  - 右から左の文字（ヘブライ語・アラビア語など）は単語ごとに CoreText で組み（アラビア文字はつながる）、段落の中で Unicode の双方向アルゴリズム（UAX #9）の主な規則（W4・W5・W7・N0・N1・N2・I1・I2・L1・L2）で段位を決め、行ごとに見える順に並べる。右から左の中の括弧は左右を反転して描く。
  - 段落の方向（`STBlockStyle.direction`: ltr・rtl・auto）。右から左の段落は、左から右として組んだ行をその行の枠の中で反転してから、段位の高い範囲を戻す。行頭・字下げ・揃え（start・end）・行の外のリスト記号が右に来る。
  - 書式の `bidi`（`STBidiSpan` の並び。外側から）は isolate（HTML の inline の dir・bdi・bdo、unicode-bidi）。中は別の並びとして段位を解き、外からは 1 つの中立の文字に見える。`overrides` は中の文字をすべてその方向として扱う（bdo）。埋め込み（embed）も isolate として扱う。
  - 表（`STTable.rightToLeft`）は 1 列目を右に置く。行の中の箱は、範囲の文字が並んだ見た目の両端で描く。
  - 単語の間に空白を置かない文字（タイ語・ラオ語・クメール語・ミャンマー語）は、システムの辞書で単語に分け、その間で改行できる。
  - 書式の `language`（lang）が中国語・韓国語のとき、漢字とハングルをその言語の書体（PingFang SC / TC / HK、宋体があればそれ、Apple SD Gothic Neo）で組む。
- **両端揃えと和欧間（読み手の既定）**: 日本語の電子書籍に向けて、本が揃えを指定しないときは両端揃え（`STReaderSettings.justifies`、既定はオン）、和欧間・和数間を指定しないときは四分アキ（`STReaderSettings.autospaces`、既定はオン）にする。オフにすると行頭揃え・ベタ組みになる。本が指定したことは `STBlockStyle.alignGiven`・`autospaceGiven` で示し、そのときは本の指定に従う（中央・行末揃えは指定がなくてもそのまま）。本がハイフンの指定（hyphens）をしていない（`STBlockStyle.hyphensGiven` が偽の）段落は、均等配置のとき欧文の単語をハイフンで分け、欧文の行が単語の間で大きく空かないようにする。段落の言語が日本語・中国語・韓国語のように辞書のない言語なら、欧文の単語は英語の辞書で分ける。和欧間の四分は字の送りとは別に持ち（`STItem.autospaceAfter`）、行末では取る。
- **縦中横（読み手の指定）**: `STReaderSettings.combinesDigits` で、本が指定していない縦組みの半角数字（指定の桁数まで）と !? を縦中横にする。
- **画像（追加）**: object-fit・object-position、合成モード、不透明度（opacity は文字・背景・画像の透明度として）。
- **行の高さ**: 1 か所（`STReaderSettings.lineHeight(of:)`）で決める。本が指定した行の高さ（`STBlockStyle.lineHeightGiven`）が `tightLineHeight`（1.5）未満なら、詰めたまま使う（年表・表・見出し）。それ以外は `minimumLineHeight` まで広げる。`followsBookLineHeights` では本の指定をそのまま使い、指定のない行は `normalLineHeight`（1.5）。
- **語間・改行しない・影**: `STTextStyle.wordSpacing`（word-spacing。空白の幅に加える）、`noWrap`（white-space: nowrap。その文字どうしの間では改行しない）、`textShadows`（text-shadow。影を描いてから本体を描く。オフセットとぼかしはデバイス空間で指定）。

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
                                 settings: settings, scale: 2, boxes: section.boxes, image: { id in nil })

// ページの上の文字の位置（選択・検索・リンク用）
let characters = pages[0].characters(geometry: geometry, writingMode: .vertical)
let rubies = pages[0].rubies
```

各ページは、章の文字列の中で自分がどこからどこまでかを持っています（`STPage.range`、UTF-16 単位）。そのため、文字の大きさを変えて組み直しても、同じ場所を指せます。

## ファイル

| ファイル | 内容 |
| --- | --- |
| `STPageModel.swift` | 文書の形（`STSection` `STBlock` `STInline`）、書式（`STTextStyle` `STBlockStyle`）、箱・表・段組・書字方向の混在（`STBox` `STTable` `STColumns` `STFlow`）、読み手の設定（`STReaderSettings`） |
| `STFontBook.swift` | 書体の選択（本の face・イタリック・OpenType の機能）と字形のキャッシュ、単語ごとの組み、縦組み用字形（上流の GSUB 読みを鍵の中で呼ぶ） |
| `STCharacterClass.swift` | 文字の性質（縦組みでの向き、約物、禁則、ぶら下げ、単語の文字）のキャッシュ |
| `STTypesetter.swift` | 行に分け、詰め、揃え、ページに詰める。箱・表・回り込み・段組・書字方向の混在のレイアウト |
| `STPageRenderer.swift` | `CGContext` に描く（箱・背景・罫・影・グラデーション・行の中の箱・ルビ・圏点・線） |
| `STPageQueries.swift` | ページの上の文字・ルビ・ブロック・画像の位置（`pictures` は単独・回り込みの画像、`allPictures` は行の中や別の組み方向のブロックの中の画像も含めて、描く位置で返す） |
| `STBidi.swift` | 双方向アルゴリズム（UAX #9 の主な規則）、isolate、行ごとの並べ替え |
| `Tests/stone_engineTests/STJLREQTests.swift` | JLREQ に照らしたテスト（約物の詰め、ルビの行の行送り、追い込み・追い出し、伸ばす所、和欧間、均等配置の既定と最終行、読み手の設定、分割禁止、グループルビ、ルビの掛けと行頭・行末、熟語ルビ、強制改行の後の始め括弧、ASCII の引用符、縦中横の字形、縦組みの引用符） |
| `Tests/stone_engineTests/STLineBreakTests.swift` | 禁則と分離禁止のテスト（stone.xcodeproj のないフォルダで `xcodebuild test -scheme stone_engine`: Package.swift・Sources・Tests だけを別のフォルダに置いて動かす） |

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
- 表・段組・書字方向の混在・回り込みは、中身のブロックをそのブロックの後ろに並べ、範囲（`end`）で指す形です。本文の位置（`STBlock.offset`）はふつうのブロックと同じように数えます。
- 段組は段の長さを二分探索で求めるので、段組のある章は組むのに時間がかかります（100ms ほど）。
- 箱を描くには、`STPageRenderer` に `boxes`（`STSection.boxes`）を渡してください。
- macOS 向けのビルドは、上流の `main` と同じく通りません（`STContext.swift` などが UIKit を使っているため）。この層そのものは CoreGraphics・CoreText・Foundation だけを使います。
