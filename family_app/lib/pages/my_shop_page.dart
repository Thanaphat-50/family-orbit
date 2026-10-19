import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';
import '../widgets/market_sheets.dart';
import 'product_form_page.dart';
import 'shop_form_page.dart';

// =======================================================
// บัญชีผู้ขาย
// - ยังไม่มีร้าน: ชวนเปิดร้าน
// - มีร้านแล้ว: สถานะร้าน สินค้า ข้อมูลติดต่อ และแก้ไขข้อมูล
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

  // โหลดข้อมูลร้านไม่สำเร็จ (แยกจาก "ยังไม่มีร้าน")
  String? loadError;

  // มีการเปลี่ยนแปลง → หน้าตลาดโหลดข้อมูลใหม่
  bool changed = false;

  // สินค้าของร้าน
  List<Map<String, dynamic>> products = [];
  bool productsLoaded = false;
  int productLimit = 30;

  // สินค้าที่กำลังซ่อน/แสดง/ลบ (กันกดซ้ำ)
  final Set<int> busyProductIds = {};

  @override
  void initState() {
    super.initState();
    refreshAll();
  }

  Future<void> refreshAll() async {
    await Future.wait([loadShop(), loadProducts()]);
  }

  Future<void> loadProducts() async {
    try {
      final result = await MarketService.getMyProducts();

      if (!mounted) return;

      if (result['status'] == true) {
        final dynamic raw = result['products'];

        setState(() {
          products = raw is List
              ? raw
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList()
              : [];
          productLimit = (result['limit'] as num?)?.toInt() ?? productLimit;
          productsLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    }
  }

  Future<void> loadShop() async {
    setState(() {
      isLoading = shop == null;
      loadError = null;
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
        final String message =
            result['message']?.toString() ?? 'โหลดข้อมูลร้านไม่สำเร็จ';

        setState(() {
          loadError = message;
        });

        showMessage(message);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadError = e.toString();
        });

        showMessage(e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // สมัครเปิดร้านใหม่
  Future<void> openShopForm() async {
    final dynamic created = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const ShopFormPage()));

    if (created is Map && mounted) {
      setState(() {
        shop = Map<String, dynamic>.from(created);
        changed = true;
      });

      await loadProducts();
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

  // =====================================================
  // จัดการสินค้า
  // =====================================================

  Future<void> openProductForm([Map<String, dynamic>? product]) async {
    final dynamic saved = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductFormPage(
          product: product,
          defaultCategory: shop?['category']?.toString(),
        ),
      ),
    );

    if (saved is Map && mounted) {
      changed = true;

      await loadProducts();
    }
  }

  Future<void> toggleProductStatus(Map<String, dynamic> product) async {
    final int? id = (product['id'] as num?)?.toInt();

    if (id == null || busyProductIds.contains(id)) return;

    final String next = product['status'] == 'hidden' ? 'active' : 'hidden';

    setState(() {
      busyProductIds.add(id);
    });

    try {
      final result = await MarketService.setProductStatus(id, next);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          product['status'] = next;
          changed = true;
        });
      }

      showMessage(result['message']?.toString() ?? 'บันทึกแล้ว');
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          busyProductIds.remove(id);
        });
      }
    }
  }

  Future<void> confirmDeleteProduct(Map<String, dynamic> product) async {
    final int? id = (product['id'] as num?)?.toInt();

    if (id == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ลบสินค้านี้?'),
          content: Text('"${product['title']}" และรูปทั้งหมดจะถูกลบถาวร'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ลบสินค้า'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      busyProductIds.add(id);
    });

    try {
      final result = await MarketService.deleteProduct(id);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          products.removeWhere((item) => item['id'] == product['id']);
          changed = true;
        });
      }

      showMessage(result['message']?.toString() ?? 'ลบสินค้าแล้ว');
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          busyProductIds.remove(id);
        });
      }
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

  // =====================================================
  // รายการสินค้าของร้าน
  // =====================================================

  List<Widget> buildProductsSection(Map<String, dynamic> data) {
    final bool suspended = data['status'] == 'suspended';

    final bool canAdd = !suspended && products.length < productLimit;

    return [
      Row(
        children: [
          Expanded(
            child: Text(
              productsLoaded
                  ? 'สินค้าของร้าน (${products.length}/$productLimit)'
                  : 'สินค้าของร้าน',
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (canAdd)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: marketColor,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => openProductForm(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('เพิ่มสินค้า'),
            ),
        ],
      ),
      if (data['status'] == 'pending' || data['status'] == 'rejected')
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'เตรียมสินค้าไว้ก่อนได้ จะแสดงในตลาดเมื่อร้านผ่านการตรวจสอบ',
            style: TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
        ),
      const SizedBox(height: 12),
      if (!productsLoaded)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        )
      else if (products.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
          decoration: cardDecoration(),
          child: const Column(
            children: [
              Icon(Icons.inventory_2_outlined, color: marketColor, size: 34),
              SizedBox(height: 10),
              Text(
                'ยังไม่มีสินค้า',
                style: TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'กด "เพิ่มสินค้า" เพื่อลงสินค้าชิ้นแรก',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        )
      else
        ...products.map((product) => buildProductTile(product, suspended)),
    ];
  }

  Widget buildProductTile(Map<String, dynamic> product, bool suspended) {
    final List<dynamic> images = (product['images'] as List?) ?? const [];

    final String? thumbnail = images.isNotEmpty && images.first is Map
        ? (images.first as Map)['url']?.toString()
        : null;

    final int? id = (product['id'] as num?)?.toInt();

    final bool busy = id != null && busyProductIds.contains(id);

    final bool hiddenByOwner = product['status'] == 'hidden';

    final bool hiddenByAdmin = product['hidden_at'] != null;

    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: cardDecoration(),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: busy || suspended ? null : () => openProductForm(product),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: thumbnail == null
                        ? const ColoredBox(color: Color(0xFFEDEFF5))
                        : Image.network(
                            thumbnail,
                            fit: BoxFit.cover,
                            cacheWidth: 220,
                            errorBuilder: (context, error, stackTrace) {
                              return const ColoredBox(color: Color(0xFFEDEFF5));
                            },
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product['title']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.navy,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        formatPrice(product['price']),
                        style: const TextStyle(
                          color: marketColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (hiddenByAdmin || hiddenByOwner) ...[
                        const SizedBox(height: 4),
                        Text(
                          hiddenByAdmin
                              ? 'ถูกซ่อนโดยผู้ดูแล'
                              : 'ซ่อนอยู่ ผู้ซื้อมองไม่เห็น',
                          style: TextStyle(
                            color: hiddenByAdmin
                                ? AppColors.danger
                                : AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'ตัวเลือกสินค้า',
                  enabled: !busy,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: AppColors.muted,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        openProductForm(product);
                      case 'toggle':
                        toggleProductStatus(product);
                      case 'delete':
                        confirmDeleteProduct(product);
                    }
                  },
                  itemBuilder: (context) {
                    return [
                      if (!suspended)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('แก้ไขสินค้า'),
                        ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          hiddenByOwner ? 'แสดงสินค้า' : 'ซ่อนสินค้า',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'ลบสินค้า',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ];
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // ยังไม่มีร้าน → ชวนเปิดร้าน
  // =====================================================

  Widget buildNoShop() {
    const steps = [
      (Icons.edit_note_rounded, 'กรอกข้อมูลร้าน เบอร์โทร และพื้นที่ขาย'),
      (Icons.verified_outlined, 'ผู้ดูแลตรวจสอบร้าน แจ้งผลในหน้าการแจ้งเตือน'),
      (
        Icons.inventory_2_outlined,
        'ลงสินค้าได้ 30 ชิ้น ให้ทุกครอบครัวในแอปเห็น',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: marketColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: marketColor,
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'เปิดร้านในแอป',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'ฟรีช่วงเปิดตัว ขายของกิน ของใช้ หรือบริการให้ครอบครัวในชุมชน',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          decoration: cardDecoration(),
          child: Column(
            children: [
              for (final (icon, text) in steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(icon, color: marketColor, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: AppColors.navy,
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: marketColor,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: openShopForm,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('เปิดร้าน'),
        ),
      ],
    );
  }

  Widget buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              loadError ?? 'โหลดข้อมูลร้านไม่สำเร็จ',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.navy),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: refreshAll,
              child: const Text('ลองอีกครั้ง'),
            ),
          ],
        ),
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
          title: const Text('บัญชีผู้ขาย'),
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
            ? (loadError != null ? buildLoadError() : buildNoShop())
            : RefreshIndicator(
                onRefresh: refreshAll,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    buildHeader(data),
                    const SizedBox(height: 14),
                    buildStatusCard(data),
                    const SizedBox(height: 24),
                    ...buildProductsSection(data),
                    const SizedBox(height: 24),
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
