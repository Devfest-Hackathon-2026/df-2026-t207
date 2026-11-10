import 'package:flutter/material.dart';

import '../app/app_loading.dart';

import 'auth_background.dart';
import 'auth_layout.dart';

/// 名前の入力画面。保存処理はアプリの接続側に渡す。
class NameSetupScreen extends StatefulWidget {
  const NameSetupScreen({
    super.key,
    required this.onContinue,
    this.initialName = '',
  });

  final Future<void> Function(String name) onContinue;
  final String initialName;

  @override
  State<NameSetupScreen> createState() => _NameSetupScreenState();
}

class _NameSetupScreenState extends State<NameSetupScreen> {
  late final TextEditingController _name;
  bool _saving = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onContinue(name);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff282824),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AuthBackground(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 32).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: '戻る',
                            onPressed: () => Navigator.of(context).maybePop(),
                            color: Colors.black,
                            icon: const Icon(Icons.arrow_back),
                          ),
                        ),
                        SizedBox(
                          height: (constraints.maxHeight * 0.63 - 56).clamp(
                            0,
                            double.infinity,
                          ),
                        ),
                        const Text(
                          'アカウント名は？',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            height: 1.35,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: authSubtitleMinHeight,
                          ),
                          child: const Text(
                            'いつでも変更できます',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        SizedBox(height: authActionGap(constraints.maxHeight)),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _name,
                                enabled: !_saving,
                                maxLength: 20,
                                textInputAction: TextInputAction.done,
                                onChanged: (_) => setState(() {}),
                                onSubmitted: (_) => _submit(),
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'アカウント名を入力',
                                  hintStyle: const TextStyle(
                                    color: Colors.white70,
                                  ),
                                  counterText: '',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(7),
                                    borderSide: const BorderSide(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(7),
                                    borderSide: const BorderSide(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: FilledButton(
                                onPressed: _saving || _name.text.trim().isEmpty
                                    ? null
                                    : _submit,
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black,
                                ),
                                child: _saving
                                    ? const AppLoadingIndicator()
                                    : const Icon(
                                        Icons.arrow_forward,
                                        semanticLabel: '次へ',
                                      ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(
                          height: 30,
                          child: _failed
                              ? const Text(
                                  '名前を保存できませんでした。もう一度お試しください。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
