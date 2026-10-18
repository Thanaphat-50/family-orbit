import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';
import '../widgets/market_sheets.dart';
import 'shop_form_page.dart';

// =======================================================
// ร้านของฉัน: สถานะร้าน ข้อมูลติดต่อ และแก้ไขข้อมูล
// =======================================================

class MyShopPage extends StatefulWidget {
  final Map<String, dynamic>? initialShop;

  const MyShopPage({super.key, this.initialShop});

  @override
  State<MyShopPage> createState() => _MyShopPageState();
}

class _MyShopPageState extends State<MyShopPage> {
  late Map<String, dynamic>? shop = widget.initialShop;

  bool isLoading = false;

  // มีการเปลี่ยนแปลง → หน้าก่อนหน้าโหลดข้อมูลใหม่
  bool changed = false;

  @override
  void initState() {
    super.initState();
    loadShop();
  }

  Future<void> loadShop() async {
    setState(() {
      isLoading = shop == null;
    });

    try {
      final result = await MarketService.getMyShop();

      if (!mounted) return;

      if (result['status'] == true) {
        final dynamic data = result['shop'];

        setState(() {
          shop = data is Map ? Map<String, dynamic>.from(data) : null;
        });
      } else {
        showMessage(result['message']?.toString() ?? 'โหลดข้อมูลร้านไม่สำเร็จ');
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> editShop() async {
    final dynamic updated = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => ShopFormPage(shop: shop)));

    if (updated is Map && mounted) {
      setState(() {
        shop = Map<String, dynamic>.from(updated);
        changed = true;
      });
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.border),
    );
  }

  // =====================================================
  // หัวร้าน
  // =====================================================

  Widget buildHeader(Map<String, dynamic> data) {
    final String? logoUrl = data['logo_url']?.toString();

    final MarketCategory? category = findMarketCategory(data['category']);

    final ShopStatusStyle status = shopStatusStyle(data['status']);

    final String area = [
      data['district']?.toString() ?? '',
      data['province']?.toString() ?? '',
    ].where((part) => part.isNotEmpty).join(', ');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: marketColor.withValues(alpha: 0.10),
            foregroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
            child: const Icon(
              Icons.storefront_rounded,
              color: marketColor,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['name']?.toString() ?? '',
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (category != null) category.label,
                    if (area.isNotEmpty) area,
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.icon, size: 14, color: status.color),
                      const SizedBox(width: 5),
                      Text(
                        status.label,
                        style: TextStyle(
                          color: status.color,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // คำอธิบายตามสถานะ
  // =====================================================

  Widget buildStatusCard(Map<String, dynamic> data) {
    final String status = data['status']?.toString() ?? 'pending';

    final String? reason = data['status_reason']?.toString();

    final ShopStatusStyle style = shopStatusStyle(status);

    final String message = switch (status) {
      'active' =>
        'ร้านของคุณแสดงในตลาดแล้ว ผู้ซื้อติดต่อคุณได้ทางโทรศัพท์และ LINE',
      'rejected' => 'แก้ไขข้อมูลร้านตามเหตุผลด้านล่าง แล้วกดส่งตรวจอีกครั้ง',
      'suspended' =>
        'ร้านถูกซ่อนจากตลาดชั่วคราว ติดต่อผู้ดูแลหากคิดว่าเป็นความผิดพลาด',
      _ => 'ผู้ดูแลกำลังตรวจสอบร้านของคุณ เมื่อมีผลจะแจ้งในหน้าการแจ้งเตือน',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(style.icon, color: style.color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'เหตุผล: $reason',
                style: TextStyle(
                  color: style.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // ข้อมูลติดต่อ
  // =====================================================

  Widget buildContactCard(Map<String, dynamic> data) {
    final String? line = data['line_id']?.toString();

    final String? description = data['description']?.toString();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
      decoration: cardDecoration(),
      child: Column(
        children: [
          if (description != null && description.isNotEmpty)
            buildInfoRow(Icons.notes_rounded, description),
          buildInfoRow(Icons.phone_outlined, data['phone']?.toString() ?? ''),
          if (line != null && line.isNotEmpty)
            buildInfoRow(Icons.chat_outlined, 'LINE: $line'),
        ],
      ),
    );
  }

  Widget buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: marketColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? data = shop;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        Navigator.of(context).pop(changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ร้านของฉัน'),
          actions: [
            IconButton(
              tooltip: 'กฎผู้ขาย',
              onPressed: () {
                showSellerRulesDialog(context);
              },
              icon: const Icon(Icons.rule_rounded),
            ),
          ],
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : data == null
            ? const Center(
                child: Text(
                  'ยังไม่มีร้าน',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            : RefreshIndicator(
                onRefresh: loadShop,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    buildHeader(data),
                    const SizedBox(height: 14),
                    buildStatusCard(data),
                    const SizedBox(height: 14),
                    buildContactCard(data),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: marketColor,
                        minimumSize: const Size(double.infinity, 52),
                        side: const BorderSide(color: marketColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      onPressed: editShop,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(
                        data['status'] == 'rejected'
                            ? 'แก้ไขแล้วส่งตรวจอีกครั้ง'
                            : 'แก้ไขข้อมูลร้าน',
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
