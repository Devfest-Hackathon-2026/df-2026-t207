/// 初回画面の説明文と主操作の間隔。
const authSubtitleMinHeight = 24.0;

double authActionGap(double availableHeight) =>
    (80 - availableHeight * 0.03).clamp(0, double.infinity);
