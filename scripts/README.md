# scripts

デモのデータの投入 (tasks の D2、D3)。Python は seg-bench の venv (isnet・SAM・YuNet・Gemini が入っている) で、df-hack26 の一番上から実行する。Google Cloud は手元の ADC (`gcloud auth application-default login`) で触る。

| スクリプト | 何をする |
|---|---|
| `seed_demo.py <素材のフォルダ> [--prefix demo]` | D2。素材の写真を vision と同じ処理に通し、デモの人物の手持ち・今日の着姿・全身写真を Firestore と Storage に入れる。最後に api に入れる環境変数を表示する |
| `precompute_demo.py --viewer <uid> --owners <uid,...>` | D3。見る人が見られる側の服を 1 着ずつ見たとして照合し、組み合わせごとに着用イメージを作って `precomputed` に置く |

素材のフォルダ (リポジトリには入れない):

```
viewer/photo.jpg        見る人 (Web の審査員が成り代わる人) の全身写真
viewer/outfit-*.jpg     見る人の着姿 (手持ちを切り抜く)
people/<名前>.jpg       見られる側の着姿 (1 人 1 枚)
```

- 顔が残って vision の処理が止まった写真は、理由を表示して飛ばす (その人は入れない)
- 入れ直すと、その uid の前のデータは消える。着用イメージは作った物を飛ばすので、途中で止まっても再実行できる
- 壇上の分: B がアプリで自分の写真と手持ちを入れた後に `precompute_demo.py --viewer <B> --owners <A>`。A は `DEMO_UIDS` にだけ入れ、`WEB_DEMO_UIDS` には入れない
- 試験: `python -m pytest -q test_demo.py` (Firestore のエミュレータ 127.0.0.1:8181 を先に立てる)
