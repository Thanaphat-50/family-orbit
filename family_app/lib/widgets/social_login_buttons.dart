import 'package:flutter/material.dart';

import '../config/app_info.dart';
import '../services/social_auth_service.dart';
import '../theme/app_theme.dart';

// =======================================================
// ปุ่ม "ดำเนินการต่อด้วย Google / LINE / Facebook"
// แสดงเฉพาะเจ้าที่ Server เปิดใช้ (ยังไม่ตั้งค่า = ไม่แสดงปุ่ม)
// =======================================================

class SocialLoginButtons extends StatefulWidget {
  // กดปุ่มแล้ว (หน้านั้นทำการล็อกอินเอง)
  final ValueChanged<SocialProvider> onPressed;

  // ปุ่มที่กำลังทำงาน (แสดงวงหมุน)
  final SocialProvider? busy;

  final bool enabled;

  const SocialLoginButtons({
    super.key,
    required this.onPressed,
    this.busy,
    this.enabled = true,
  });

  @override
  State<SocialLoginButtons> createState() => _SocialLoginButtonsState();
}

class _SocialLoginButtonsState extends State<SocialLoginButtons> {
  List<SocialProvider> providers = const [];

  @override
  void initState() {
    super.initState();

    loadProviders();
  }

  Future<void> loadProviders() async {
    try {
      final enabled = await SocialAuthService.enabledProviders();

      if (mounted) setState(() => providers = enabled);
    } catch (_) {
      // Server ไม่ตอบ → ไม่แสดงปุ่ม (ยังเข้าสู่ระบบด้วยอีเมลได้)
    }
  }

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final provider in providers) ...[
          _SocialButton(
            provider: provider,
            busy: widget.busy == provider,
            onPressed: widget.enabled && widget.busy == null
                ? () => widget.onPressed(provider)
                : null,
          ),
          const SizedBox(height: 10),
        ],

        // สมัครด้วยบัญชีเหล่านี้ = ยอมรับข้อกำหนด (กดอ่านได้)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 14),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text(
                'การดำเนินการต่อถือว่าคุณยอมรับ',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
              buildLink('ข้อกำหนด', AppInfo.termsUrl),
              Text(
                'และ',
                style: TextStyle(color: AppColors.muted, fontSize: 11.5),
              ),
              buildLink('นโยบายความเป็นส่วนตัว', AppInfo.privacyUrl),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildLink(String label, String url) {
    return GestureDetector(
      onTap: () => AppInfo.openUrl(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final SocialProvider provider;
  final bool busy;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.provider,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final _Brand brand = _Brand.of(provider);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: Material(
        color: brand.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: brand.outlined
                  ? Border.all(color: AppColors.border)
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                SizedBox(
                  width: 28,
                  child: busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: brand.foreground,
                          ),
                        )
                      : brand.mark,
                ),
                Expanded(
                  child: Text(
                    'ดำเนินการต่อด้วย ${provider.label}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: brand.foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// สีและสัญลักษณ์ของแต่ละเจ้า (ตามสีแบรนด์)
class _Brand {
  final Color background;
  final Color foreground;
  final bool outlined;
  final Widget mark;

  const _Brand({
    required this.background,
    required this.foreground,
    required this.outlined,
    required this.mark,
  });

  static _Brand of(SocialProvider provider) {
    switch (provider) {
      case SocialProvider.google:
        return _Brand(
          background: AppColors.surface,
          foreground: AppColors.navy,
          outlined: true,
          mark: const Text(
            'G',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF4285F4),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        );

      case SocialProvider.line:
        return const _Brand(
          background: Color(0xFF06C755),
          foreground: Colors.white,
          outlined: false,
          mark: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 22),
        );

      case SocialProvider.facebook:
        return const _Brand(
          background: Color(0xFF1877F2),
          foreground: Colors.white,
          outlined: false,
          mark: Text(
            'f',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
    }
  }
}
