import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/market_data.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import '../widgets/market_widgets.dart' show ShopContactButtons;
import '../widgets/photo_viewer.dart';
import '../widgets/promptpay_qr.dart';
import 'market_shop_page.dart';

// =======================================================
// รายละเอียดคำสั่งซื้อ (ผู้ซื้อ และ ร้าน ใช้หน้าเดียวกัน)
// ปุ่มที่แสดงมาจาก order['actions'] ที่เซิร์ฟเวอร์ส่งมา
// pop กลับพร้อม true เมื่อมีการเปลี่ยนสถานะ (หน้ารายการโหลดใหม่)
// =======================================================

class OrderPage extends StatefulWidget {
  final int orderId;

  const OrderPage({super.key, required this.orderId});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  Map<String, dynamic>? order;
  String? loadError;
  bool isLoading = true;
  bool isWorking = false;
  bool changed = false;

  bool get isSeller => order?['role'] == 'seller';

  List<String> get actions => [
    for (final action in (order?['actions'] as List?) ?? const [])
      action.toString(),
  ];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => loadError = null);

    try {
      final result = await OrderService.getOrder(widget.orderId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() => order = Map<String, dynamic>.from(result['order']));
      } else {
        setState(() {
          loadError = result['message']?.toString() ?? 'ไม่พบคำสั่งซื้อนี้';
        });
      }
    } catch (e) {
      if (mounted) setState(() => loadError = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // =====================================================
  // ทำรายการ → ใช้คำสั่งซื้อล่าสุดที่เซิร์ฟเวอร์ส่งกลับ
  // =====================================================

  Future<void> run(Future<Map<String, dynamic>> Function() request) async {
    if (isWorking) return;

    setState(() => isWorking = true);

    try {
      final result = await request();

      if (!mounted) return;

      showMessage(result['message']?.toString() ?? 'ทำรายการไม่สำเร็จ');

      final dynamic latest = result['order'];

      if (latest is Map) {
        changed = true;

        setState(() => order = Map<String, dynamic>.from(latest));
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => isWorking = false);
    }
  }

  Future<void> act(String action, [Map<String, dynamic> fields = const {}]) {
    return run(() => OrderService.act(widget.orderId, action, fields));
  }

  Future<void> attachSlip() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1800,
    );

    if (file == null || !mounted) return;

    await run(() => OrderService.uploadSlip(widget.orderId, file.path));
  }

  Future<void> confirmThen({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยังก่อน'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: marketColor),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) await onConfirm();
  }

  Future<void> cancelOrder() async {
    final String? reason = await showTextDialog(
      context,
      title: 'ยกเลิกคำสั่งซื้อ?',
      label: isSeller ? 'เหตุผล (ลูกค้าจะเห็น)' : 'เหตุผล (ไม่บังคับ)',
      hint: isSeller ? 'เช่น สินค้าหมด' : 'เช่น สั่งผิด',
      confirmLabel: 'ยกเลิกคำสั่งซื้อ',
      required: isSeller,
      danger: true,
    );

    if (reason == null) return;

    await act('cancel', {'reason': reason});
  }

  Future<void> rejectSlip() async {
    final String? reason = await showTextDialog(
      context,
      title: 'สลิปไม่ถูกต้อง',
      label: 'บอกลูกค้าว่าไม่ถูกต้องตรงไหน',
      hint: 'เช่น ยอดเงินไม่ตรง / ยังไม่มีเงินเข้า',
      confirmLabel: 'ส่งให้ลูกค้าแนบใหม่',
      required: true,
    );

    if (reason == null) return;

    await act('reject-slip', {'reason': reason});
  }

  Future<void> shipOrder() async {
    final bool handover = order?['is_handover'] == true;

    final ({String tracking, String note})? result = await showShipDialog(
      context,
      handover: handover,
      // โอนเงิน: เตือนให้เช็กยอดในบัญชีก่อนส่ง
      paidAmount: order?['is_transfer'] == true
          ? formatPrice(order?['total'])
          : null,
    );

    if (result == null) return;

    await act('ship', {
      'tracking_number': result.tracking,
      'seller_note': result.note,
    });
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));

    showMessage(message);
  }

  // =====================================================
  // ข้อความบอกว่าตอนนี้ต้องทำอะไร
  // =====================================================

  String statusHint(Map<String, dynamic> data) {
    final String status = data['status']?.toString() ?? '';
    final bool transfer = data['is_transfer'] == true;
    final bool handover = data['is_handover'] == true;
    final String total = formatPrice(data['total']);

    if (isSeller) {
      return switch (status) {
        'awaiting_payment' =>
          'รอลูกค้าโอน $total ภายใน ${formatDateTime(data['payment_deadline'])}',
        'payment_review' =>
          'ลูกค้าแนบสลิปแล้ว แต่ระบบตรวจอัตโนมัติไม่ได้ เช็กในแอปธนาคารว่าเงินเข้าครบ $total แล้วกดยืนยัน',
        'preparing' =>
          transfer
              ? 'ลูกค้าชำระ $total แล้ว ${handover ? 'ส่งมอบสินค้า' : 'ส่งสินค้า'}ได้เลย'
              : handover
              ? 'เตรียมสินค้า เก็บเงิน $total ตอนลูกค้ารับของ แล้วกด "ส่งมอบสินค้าแล้ว"'
              : 'ส่งสินค้า (เก็บเงินปลายทาง $total) แล้วกด "ส่งสินค้าแล้ว"',
        'shipped' => 'รอลูกค้ากดได้รับสินค้า',
        'completed' => 'คำสั่งซื้อสำเร็จ',
        _ => cancelText(data),
      };
    }

    return switch (status) {
      'awaiting_payment' =>
        'กรุณาโอน $total แล้วแนบสลิปภายใน ${formatDateTime(data['payment_deadline'])}',
      'payment_review' => 'ส่งสลิปแล้ว รอร้านตรวจยอดเงินในบัญชี',
      'preparing' =>
        transfer
            ? 'ชำระเงินแล้ว รอร้านจัดส่งสินค้า'
            : 'รอร้านจัดส่ง เตรียมเงิน $total ไว้จ่ายตอนรับของ',
      'shipped' =>
        'ได้รับสินค้าแล้วกด "ได้รับสินค้าแล้ว" '
            '(ไม่กดภายใน ${formatDateTime(data['auto_complete_at'], withTime: false)} ระบบจะยืนยันให้)',
      'completed' => 'ได้รับสินค้าแล้ว ขอบคุณที่สั่งซื้อ',
      _ => cancelText(data),
    };
  }

  String cancelText(Map<String, dynamic> data) {
    final String by = switch (data['cancelled_by']) {
      'buyer' => isSeller ? 'ลูกค้ายกเลิก' : 'คุณยกเลิก',
      'seller' => isSeller ? 'คุณยกเลิก' : 'ร้านยกเลิก',
      _ => 'ระบบยกเลิก',
    };

    final String reason = data['cancel_reason']?.toString() ?? '';

    return reason.isEmpty ? by : '$by: $reason';
  }

  // =====================================================
  // UI
  // =====================================================

  Widget card({required Widget child, Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: AppDecorations.cardBorder,
        boxShadow: AppDecorations.cardShadow,
      ),
      child: child,
    );
  }

  Widget title(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.navy,
          fontSize: 15,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget infoRow(IconData icon, String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: AppColors.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget buildStatus(Map<String, dynamic> data) {
    final ShopStatusStyle style = orderStatusStyle(data['status']);

    return card(
      color: style.color.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(style.icon, color: style.color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data['status_label']?.toString() ?? style.label,
                  style: TextStyle(
                    color: style.color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            statusHint(data),
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          buildSteps(data),
        ],
      ),
    );
  }

  // ขั้นตอน: สั่งซื้อ → (ชำระเงิน) → ส่งสินค้า → สำเร็จ
  Widget buildSteps(Map<String, dynamic> data) {
    final bool transfer = data['is_transfer'] == true;

    final List<(String, bool)> steps = [
      ('สั่งซื้อ', true),
      if (transfer) ('ชำระเงิน', data['paid_at'] != null),
      (
        data['is_handover'] == true ? 'ส่งมอบ' : 'ส่งสินค้า',
        data['shipped_at'] != null,
      ),
      ('สำเร็จ', data['completed_at'] != null),
    ];

    final bool cancelled = data['status'] == 'cancelled';

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Icon(
                  steps[i].$2
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: steps[i].$2 && !cancelled
                      ? AppColors.success
                      : AppColors.muted,
                ),
                const SizedBox(height: 4),
                Text(
                  steps[i].$1,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 11.5,
                    fontWeight: steps[i].$2 ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ผู้ซื้อ: QR พร้อมเพย์ / เลขบัญชีของร้าน + แนบสลิป
  Widget buildPayment(Map<String, dynamic> data) {
    final Map? payment = data['payment'] as Map?;

    final String amount = formatPrice(data['total']);

    final String? note = data['payment_note']?.toString();

    return card(
      child: Column(
        children: [
          if (note != null && note.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'ร้านแจ้งว่าสลิปไม่ถูกต้อง: $note',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            data['payment_label']?.toString() ?? 'ชำระเงิน',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          Text(
            amount,
            style: const TextStyle(
              color: marketColor,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (payment == null)
            Text(
              'ร้านยังไม่ได้ตั้งค่าบัญชีรับเงิน กรุณาติดต่อร้าน',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.danger, fontSize: 13),
            )
          else if (payment['method'] == 'promptpay') ...[
            PromptPayQrImage(
              payload: payment['promptpay_payload']?.toString() ?? '',
            ),
            const SizedBox(height: 10),
            Text(
              '${payment['account_name'] ?? ''}\nพร้อมเพย์ ${payment['promptpay_id'] ?? ''}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final String? error = await sharePromptPayQr(
                    payload: payment['promptpay_payload']?.toString() ?? '',
                    amount: amount,
                    fileTag: 'order_${data['id']}',
                  );

                  if (error != null) showMessage(error);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text('บันทึก / แชร์รูป QR'),
              ),
            ),
          ] else ...[
            infoRow(
              Icons.account_balance_outlined,
              payment['bank_name']?.toString() ?? '',
            ),
            infoRow(
              Icons.numbers_rounded,
              payment['account_number']?.toString() ?? '',
              trailing: TextButton(
                onPressed: () => copy(
                  payment['account_number']?.toString() ?? '',
                  'คัดลอกเลขบัญชีแล้ว',
                ),
                child: const Text('คัดลอก'),
              ),
            ),
            infoRow(
              Icons.person_outline_rounded,
              'ชื่อบัญชี ${payment['account_name'] ?? ''}',
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'แนบสลิปภายใน ${formatDateTime(data['payment_deadline'])}',
            style: TextStyle(
              color: AppColors.danger,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isWorking || payment == null ? null : attachSlip,
              style: FilledButton.styleFrom(
                backgroundColor: marketColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('แนบสลิปการโอน'),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSlip(Map<String, dynamic> data) {
    final String url = data['slip_url'].toString();

    return card(
      child: Row(
        children: [
          GestureDetector(
            onTap: () => showPhotoViewer(context, urls: [url]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                width: 72,
                height: 96,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  width: 72,
                  height: 96,
                  child: ColoredBox(color: AppColors.fill),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สลิปการโอน',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'แนบเมื่อ ${formatDateTime(data['slip_uploaded_at'])}\nกดรูปเพื่อดูขนาดเต็ม',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildItem(Map<String, dynamic> data) {
    final String? imageUrl = data['image_url']?.toString();

    final double shipping =
        double.tryParse('${data['shipping_fee'] ?? 0}') ?? 0;

    Widget line(String label, String value, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: bold ? AppColors.navy : AppColors.muted,
                  fontSize: 13.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: bold ? marketColor : AppColors.navy,
                fontSize: bold ? 17 : 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    // คำสั่งซื้อเก่าที่ไม่มีรายการแยก → ใช้ข้อมูลสรุปของคำสั่งซื้อ
    final List items = (data['items'] as List?)?.isNotEmpty == true
        ? data['items'] as List
        : [
            {
              'title': data['product_title'],
              'unit_price': data['unit_price'],
              'quantity': data['quantity'],
              'subtotal':
                  (double.tryParse('${data['unit_price']}') ?? 0) *
                  ((data['quantity'] as num?) ?? 1),
              'image_url': imageUrl,
            },
          ];

    final double itemsTotal = items.fold(
      0,
      (sum, item) => sum + (double.tryParse('${item['subtotal'] ?? 0}') ?? 0),
    );

    return card(
      child: Column(
        children: [
          for (final item in items)
            if (item is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: item['image_url'] == null
                            ? ColoredBox(color: AppColors.fill)
                            : Image.network(
                                item['image_url'].toString(),
                                fit: BoxFit.cover,
                                cacheWidth: 200,
                                errorBuilder: (context, error, stackTrace) =>
                                    ColoredBox(color: AppColors.fill),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (item['variant_name'] != null)
                            Text(
                              'ตัวเลือก: ${item['variant_name']}',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          Text(
                            '${formatPrice(item['unit_price'])} × ${item['quantity']}',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatPrice(item['subtotal']),
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
          const Divider(height: 12),
          line('ค่าสินค้า', formatPrice(itemsTotal)),
          line('ค่าส่ง', shipping > 0 ? formatPrice(shipping) : 'ไม่มี'),
          const Divider(height: 16),
          line('ยอดรวม', formatPrice(data['total']), bold: true),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ชำระเงิน: ${data['payment_label'] ?? ''}',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildDelivery(Map<String, dynamic> data) {
    final String phone = data['recipient_phone']?.toString() ?? '';
    final String address = data['address']?.toString() ?? '';
    final String note = data['note']?.toString() ?? '';
    final String tracking = data['tracking_number']?.toString() ?? '';
    final String sellerNote = data['seller_note']?.toString() ?? '';

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(data['delivery_label']?.toString() ?? 'การรับสินค้า'),
          infoRow(
            Icons.person_outline_rounded,
            '${data['recipient_name'] ?? ''} · $phone',
            trailing: isSeller && phone.isNotEmpty
                ? IconButton(
                    tooltip: 'โทรหาลูกค้า',
                    onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                    icon: const Icon(Icons.call_rounded, color: marketColor),
                  )
                : null,
          ),
          if (address.isNotEmpty)
            infoRow(
              Icons.home_outlined,
              address,
              trailing: isSeller
                  ? TextButton(
                      onPressed: () => copy(address, 'คัดลอกที่อยู่แล้ว'),
                      child: const Text('คัดลอก'),
                    )
                  : null,
            ),
          if (note.isNotEmpty)
            infoRow(Icons.sticky_note_2_outlined, 'ฝากถึงร้าน: $note'),
          if (tracking.isNotEmpty)
            infoRow(
              Icons.local_shipping_outlined,
              'เลขพัสดุ $tracking',
              trailing: TextButton(
                onPressed: () => copy(tracking, 'คัดลอกเลขพัสดุแล้ว'),
                child: const Text('คัดลอก'),
              ),
            ),
          if (sellerNote.isNotEmpty)
            infoRow(Icons.storefront_outlined, 'ร้านแจ้ง: $sellerNote'),
        ],
      ),
    );
  }

  Widget buildParty(Map<String, dynamic> data) {
    final Map shop = (data['shop'] as Map?) ?? const {};
    final Map? buyer = data['buyer'] as Map?;

    if (isSeller) {
      return card(
        child: infoRow(
          Icons.account_circle_outlined,
          'ลูกค้า: ${buyer?['name'] ?? data['recipient_name'] ?? ''}',
        ),
      );
    }

    final int? shopId = (shop['id'] as num?)?.toInt();

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: shopId == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => MarketShopPage(shopId: shopId),
                    ),
                  ),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, color: marketColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shop['name']?.toString() ?? '',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: marketColor),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ShopContactButtons(
            phone: shop['phone']?.toString(),
            lineId: shop['line_id']?.toString(),
          ),
        ],
      ),
    );
  }

  // ประวัติสถานะ (ใหม่สุดอยู่บน) จากเซิร์ฟเวอร์
  Widget buildTimes(Map<String, dynamic> data) {
    final List history = (data['history'] as List?) ?? const [];

    String actorLabel(dynamic actor) => switch (actor) {
      'buyer' => isSeller ? 'ลูกค้า' : 'คุณ',
      'seller' => isSeller ? 'คุณ' : 'ร้าน',
      _ => 'ระบบ',
    };

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('เลขที่ ${data['code'] ?? ''}'),
          if (history.isEmpty)
            Text(
              'สั่งซื้อเมื่อ ${formatDateTime(data['created_at'])}',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5),
            ),
          for (int i = 0; i < history.length; i++)
            if (history[i] is Map)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Icon(
                        i == 0
                            ? Icons.radio_button_checked_rounded
                            : Icons.circle,
                        size: i == 0 ? 16 : 9,
                        color: i == 0
                            ? orderStatusStyle(data['status']).color
                            : AppColors.muted,
                      ),
                      if (i < history.length - 1)
                        Container(
                          width: 2,
                          height: 30,
                          color: AppColors.border,
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${history[i]['status_label'] ?? ''} · ${actorLabel(history[i]['actor'])}',
                            style: TextStyle(
                              color: i == 0 ? AppColors.navy : AppColors.muted,
                              fontSize: 13,
                              fontWeight: i == 0
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          if ((history[i]['note']?.toString() ?? '').isNotEmpty)
                            Text(
                              history[i]['note'].toString(),
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          Text(
                            formatDateTime(history[i]['created_at']),
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  // ปุ่มด้านล่างตามสิทธิ์ที่เซิร์ฟเวอร์ส่งมา
  List<Widget> buildActions(Map<String, dynamic> data) {
    final List<String> can = actions;
    final bool handover = data['is_handover'] == true;

    Widget primary(String label, IconData icon, VoidCallback onPressed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: marketColor,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: isWorking ? null : onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
    }

    Widget secondary(
      String label,
      VoidCallback onPressed, {
      bool danger = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: danger ? AppColors.danger : marketColor,
            side: BorderSide(color: danger ? AppColors.danger : marketColor),
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          onPressed: isWorking ? null : onPressed,
          child: Text(label),
        ),
      );
    }

    return [
      // ระบบตรวจสลิปไม่ได้ → ร้านเช็กยอดในบัญชีเอง
      if (can.contains('confirm_payment'))
        primary(
          'ยืนยันว่าได้รับเงินแล้ว',
          Icons.verified_rounded,
          () => confirmThen(
            title: 'เงินเข้าบัญชีแล้ว?',
            message:
                'เช็กในแอปธนาคารแล้วว่าได้รับ ${formatPrice(data['total'])} ครบ',
            confirmLabel: 'ยืนยันรับเงิน',
            onConfirm: () => act('confirm-payment'),
          ),
        ),
      if (can.contains('ship'))
        primary(
          handover ? 'ส่งมอบสินค้าแล้ว' : 'ส่งสินค้าแล้ว',
          handover ? Icons.handshake_outlined : Icons.local_shipping_outlined,
          shipOrder,
        ),
      if (can.contains('reject_slip'))
        secondary('สลิปไม่ถูกต้อง / เงินไม่เข้า', rejectSlip),
      if (can.contains('received'))
        primary(
          'ได้รับสินค้าแล้ว',
          Icons.inventory_rounded,
          () => confirmThen(
            title: 'ได้รับสินค้าแล้ว?',
            message: 'ตรวจสินค้าให้เรียบร้อยก่อนกดยืนยัน',
            confirmLabel: 'ได้รับแล้ว',
            onConfirm: () => act('received'),
          ),
        ),
      if (!isSeller && data['status'] == 'completed')
        secondary('รีวิวร้านนี้', () {
          final int? shopId = ((data['shop'] as Map?)?['id'] as num?)?.toInt();

          if (shopId == null) return;

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => MarketShopPage(shopId: shopId),
            ),
          );
        }),
      if (can.contains('cancel'))
        secondary('ยกเลิกคำสั่งซื้อ', cancelOrder, danger: true),
    ];
  }

  Widget buildBody(Map<String, dynamic> data) {
    final bool showPayment =
        !isSeller &&
        data['is_transfer'] == true &&
        data['status'] == 'awaiting_payment';

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          buildStatus(data),
          if (showPayment) buildPayment(data),
          if (data['slip_url'] != null) buildSlip(data),
          ...buildActions(data),
          buildItem(data),
          if (((data['payments'] as List?) ?? const []).isNotEmpty)
            buildPayments(data),
          buildDelivery(data),
          buildParty(data),
          buildTimes(data),
        ],
      ),
    );
  }

  // ประวัติการชำระเงิน (ทุกครั้งที่แนบสลิป + ผลตรวจ)
  Widget buildPayments(Map<String, dynamic> data) {
    final List payments = (data['payments'] as List?) ?? const [];

    Color colorOf(dynamic status) => switch (status) {
      'verified' || 'confirmed' => AppColors.success,
      'rejected' => AppColors.danger,
      _ => const Color(0xFF2E90FA),
    };

    return card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title('ประวัติการชำระเงิน'),
          for (final payment in payments)
            if (payment is Map)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      payment['status'] == 'rejected'
                          ? Icons.cancel_rounded
                          : payment['status'] == 'review'
                          ? Icons.hourglass_top_rounded
                          : Icons.check_circle_rounded,
                      size: 20,
                      color: colorOf(payment['status']),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            payment['status_label']?.toString() ?? '',
                            style: TextStyle(
                              color: colorOf(payment['status']),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((payment['reason']?.toString() ?? '').isNotEmpty)
                            Text(
                              payment['reason'].toString(),
                              style: TextStyle(
                                color: AppColors.navy,
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          Text(
                            [
                              if (payment['slip_amount'] != null)
                                'ยอดในสลิป ${formatPrice(payment['slip_amount'])}',
                              formatDateTime(payment['created_at']),
                            ].join(' · '),
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
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

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? data = order;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        Navigator.of(context).pop(changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isSeller ? 'คำสั่งซื้อของลูกค้า' : 'คำสั่งซื้อของฉัน'),
        ),
        body: isLoading && data == null
            ? const Center(child: CircularProgressIndicator())
            : data == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loadError ?? 'ไม่พบคำสั่งซื้อนี้',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.navy),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: load,
                        child: const Text('ลองอีกครั้ง'),
                      ),
                    ],
                  ),
                ),
              )
            : buildBody(data),
      ),
    );
  }
}

// =======================================================
// หน้าต่างพิมพ์ข้อความ (เหตุผลยกเลิก / สลิปไม่ถูกต้อง)
// คืน null เมื่อกดยกเลิก
// =======================================================

Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  required String confirmLabel,
  bool required = false,
  bool danger = false,
}) {
  final TextEditingController controller = TextEditingController();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: (value) => required && (value ?? '').trim().isEmpty
              ? 'กรุณาบอกเหตุผล'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ไม่ทำ'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? AppColors.danger : marketColor,
          ),
          onPressed: () {
            if (!(formKey.currentState?.validate() ?? false)) return;

            Navigator.of(dialogContext).pop(controller.text.trim());
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

// ร้านกดส่งสินค้า: เลขพัสดุ (ส่งพัสดุ/ส่งถึงบ้าน) + ข้อความถึงลูกค้า
Future<({String tracking, String note})?> showShipDialog(
  BuildContext context, {
  required bool handover,
  String? paidAmount,
}) {
  final TextEditingController tracking = TextEditingController();
  final TextEditingController note = TextEditingController();

  return showDialog<({String tracking, String note})>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(handover ? 'ส่งมอบสินค้าแล้ว?' : 'ส่งสินค้าแล้ว?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (paidAmount != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'เช็กในแอปธนาคารแล้วว่าได้รับเงิน $paidAmount ครบ',
                style: TextStyle(
                  color: AppColors.danger,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!handover)
            TextField(
              controller: tracking,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'เลขพัสดุ (ไม่บังคับ)',
                hintText: 'เช่น TH0123456789',
              ),
            ),
          TextField(
            controller: note,
            maxLength: 500,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'ข้อความถึงลูกค้า (ไม่บังคับ)',
              hintText: 'เช่น ส่งกับไปรษณีย์ไทย',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('ยังก่อน'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: marketColor),
          onPressed: () => Navigator.of(dialogContext)
              .pop((tracking: tracking.text.trim(), note: note.text.trim())),
          child: const Text('ยืนยัน'),
        ),
      ],
    ),
  );
}
