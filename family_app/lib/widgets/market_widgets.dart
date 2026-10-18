import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/market_data.dart';
import '../theme/app_theme.dart';

// =======================================================
// การ์ดสินค้าในตาราง (หน้าตลาด / หน้าร้าน)
// =======================================================

class MarketProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  // หน้าร้านไม่ต้องแสดงชื่อร้านซ้ำ
  final bool showShop;

  const MarketProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showShop = true,
  });

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = product['image_url']?.toString();

    final dynamic shop = product['shop'];

    final String shopLine = shop is Map
        ? [
            shop['name']?.toString() ?? '',
            shop['province']?.toString() ?? '',
          ].where((part) => part.isNotEmpty).join(' · ')
        : '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // รูปใช้ความสูงที่เหลือจากข้อความ (ไม่ล้นเมื่อขยายตัวอักษร)
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: imageUrl == null
                      ? const ColoredBox(
                          color: Color(0xFFF3EEE9),
                          child: Icon(
                            Icons.shopping_bag_outlined,
                            color: marketColor,
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 500,
                          loadingBuilder: (context, child, progress) {
                            return progress == null
                                ? child
                                : const ColoredBox(color: Color(0xFFF3EEE9));
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const ColoredBox(
                              color: Color(0xFFF3EEE9),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.muted,
                              ),
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['title']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      formatPrice(product['price']),
                      style: const TextStyle(
                        color: marketColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (showShop && shopLine.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        shopLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================
// ปุ่มติดต่อร้าน: โทร / LINE
// เปิดแอปโทรศัพท์หรือ LINE ไม่ได้ → คัดลอกให้แทน
// =======================================================

class ShopContactButtons extends StatelessWidget {
  final String? phone;
  final String? lineId;

  const ShopContactButtons({super.key, this.phone, this.lineId});

  Future<void> open(
    BuildContext context, {
    required Uri uri,
    required String copyText,
    required String copiedMessage,
  }) async {
    bool opened = false;

    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }

    if (opened || !context.mounted) return;

    await Clipboard.setData(ClipboardData(text: copyText));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copiedMessage)));
  }

  // LINE ID ส่วนตัว → line.me/R/ti/p/~id, บัญชีทางการ (@id) → line.me/R/ti/p/@id
  Uri lineUri(String id) {
    final String path = id.startsWith('@')
        ? Uri.encodeComponent(id)
        : '~${Uri.encodeComponent(id)}';

    return Uri.parse('https://line.me/R/ti/p/$path');
  }

  @override
  Widget build(BuildContext context) {
    final String? phoneNumber = phone?.trim().isNotEmpty == true
        ? phone!.trim()
        : null;

    final String? line = lineId?.trim().isNotEmpty == true
        ? lineId!.trim()
        : null;

    return Row(
      children: [
        if (phoneNumber != null)
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: marketColor,
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => open(
                context,
                uri: Uri(scheme: 'tel', path: phoneNumber),
                copyText: phoneNumber,
                copiedMessage: 'คัดลอกเบอร์ $phoneNumber แล้ว',
              ),
              icon: const Icon(Icons.call_rounded, size: 20),
              label: const Text('โทรหาร้าน'),
            ),
          ),
        if (phoneNumber != null && line != null) const SizedBox(width: 10),
        if (line != null)
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF06C755),
                side: const BorderSide(color: Color(0xFF06C755)),
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () => open(
                context,
                uri: lineUri(line),
                copyText: line,
                copiedMessage: 'คัดลอก LINE ID $line แล้ว',
              ),
              icon: const Icon(Icons.chat_rounded, size: 20),
              label: const Text('LINE'),
            ),
          ),
      ],
    );
  }
}

// =======================================================
// คำเตือนความปลอดภัยในการซื้อขาย
// =======================================================

class MarketSafetyNote extends StatelessWidget {
  const MarketSafetyNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.softWarm,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: marketColor, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'แอปไม่ได้รับชำระเงินแทน ควรนัดดูสินค้าหรือตรวจสอบร้าน'
              'ก่อนโอนเงิน หากพบการโกงกด "รายงาน" ได้ทันที',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
