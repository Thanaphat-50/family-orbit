import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import 'order_page.dart';

// =======================================================
// สั่งซื้อสินค้า: จำนวน → วิธีรับสินค้า → ผู้รับ → วิธีชำระเงิน → ยืนยัน
// สั่งแล้วไปหน้าคำสั่งซื้อ (โอนเงิน → เห็น QR ทันที / ปลายทาง → รอร้านจัดส่ง)
// =======================================================

class CheckoutPage extends StatefulWidget {
  final int productId;

  const CheckoutPage({super.key, required this.productId});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController noteController = TextEditingController();

  Map<String, dynamic>? data;
  String? loadError;
  bool isLoading = true;
  bool isSubmitting = false;

  int quantity = 1;
  String? delivery;
  String? payment;

  Map<String, String> serverErrors = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final result = await OrderService.getCheckout(widget.productId);

      if (!mounted) return;

      if (result['status'] != true) {
        setState(() {
          loadError =
              result['message']?.toString() ?? 'สั่งซื้อสินค้านี้ไม่ได้';
        });
        return;
      }

      final Map recipient = (result['recipient'] as Map?) ?? const {};

      nameController.text = recipient['name']?.toString() ?? '';
      phoneController.text = recipient['phone']?.toString() ?? '';
      addressController.text = recipient['address']?.toString() ?? '';

      setState(() {
        data = result;

        final List methods = deliveryOptions();

        // มีวิธีเดียว → เลือกให้เลย
        if (methods.length == 1) selectDelivery(methods.first['key']);
      });
    } catch (e) {
      if (mounted) setState(() => loadError = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // =====================================================
  // ข้อมูลที่เลือก
  // =====================================================

  List<Map<String, dynamic>> deliveryOptions() {
    final dynamic raw = data?['delivery_methods'];

    return raw is List
        ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : [];
  }

  Map<String, dynamic>? get selectedDelivery {
    for (final option in deliveryOptions()) {
      if (option['key'] == delivery) return option;
    }

    return null;
  }

  List<Map<String, dynamic>> get paymentOptions {
    final dynamic raw = selectedDelivery?['payment_methods'];

    return raw is List
        ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : [];
  }

  bool get needsAddress => selectedDelivery?['needs_address'] == true;

  double get unitPrice =>
      double.tryParse('${(data?['product'] as Map?)?['price'] ?? ''}') ?? 0;

  double get shippingFee =>
      (selectedDelivery?['shipping_fee'] as num?)?.toDouble() ?? 0;

  double get total => unitPrice * quantity + shippingFee;

  int get maxQuantity => (data?['max_quantity'] as num?)?.toInt() ?? 1;

  void selectDelivery(dynamic key) {
    delivery = key?.toString();

    // วิธีจ่ายเดิมใช้ไม่ได้กับวิธีรับใหม่ → ล้าง / มีแบบเดียว → เลือกให้
    final List<Map<String, dynamic>> options = paymentOptions;

    if (!options.any((option) => option['key'] == payment)) {
      payment = options.length == 1 ? options.first['key']?.toString() : null;
    }
  }

  // =====================================================
  // สั่งซื้อ
  // =====================================================

  Future<void> submit() async {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => serverErrors = {});

    if (delivery == null) {
      showMessage('กรุณาเลือกวิธีรับสินค้า');
      return;
    }

    if (!(formKey.currentState?.validate() ?? false)) return;

    if (payment == null) {
      showMessage('กรุณาเลือกวิธีชำระเงิน');
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final result = await OrderService.placeOrder({
        'product_id': widget.productId,
        'quantity': quantity,
        'delivery_method': delivery,
        'payment_method': payment,
        'recipient_name': nameController.text.trim(),
        'recipient_phone': phoneController.text.trim(),
        'address': needsAddress ? addressController.text.trim() : null,
        'note': noteController.text.trim(),
      });

      if (!mounted) return;

      final int? orderId = ((result['order'] as Map?)?['id'] as num?)?.toInt();

      if (result['status'] == true && orderId != null) {
        showMessage(result['message']?.toString() ?? 'สั่งซื้อแล้ว');

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => OrderPage(orderId: orderId)),
        );
        return;
      }

      final dynamic errors = result['errors'];

      if (errors is Map) {
        setState(() {
          serverErrors = {
            for (final entry in errors.entries)
              entry.key.toString(): entry.value is List
                  ? (entry.value as List).first.toString()
                  : entry.value.toString(),
          };
        });
      }

      showMessage(result['message']?.toString() ?? 'สั่งซื้อไม่สำเร็จ');
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // UI
  // =====================================================

  Widget card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: AppDecorations.cardBorder,
        boxShadow: AppDecorations.cardShadow,
      ),
      child: child,
    );
  }

  Widget sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
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

  Widget buildProduct() {
    final Map product = (data?['product'] as Map?) ?? const {};
    final Map shop = (data?['shop'] as Map?) ?? const {};

    final String? imageUrl = product['image_url']?.toString();

    return card(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 72,
              height: 72,
              child: imageUrl == null
                  ? ColoredBox(color: AppColors.fill)
                  : Image.network(imageUrl, fit: BoxFit.cover, cacheWidth: 220),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product['title']?.toString() ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shop['name']?.toString() ?? '',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatPrice(product['price'])} · เหลือ ${product['stock'] ?? 0} ชิ้น',
                  style: const TextStyle(
                    color: marketColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildQuantity() {
    Widget stepButton(IconData icon, VoidCallback? onTap) {
      return IconButton.filledTonal(
        onPressed: isSubmitting ? null : onTap,
        icon: Icon(icon),
      );
    }

    return card(
      child: Row(
        children: [
          Expanded(
            child: Text(
              'จำนวน',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          stepButton(
            Icons.remove_rounded,
            quantity > 1 ? () => setState(() => quantity--) : null,
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          stepButton(
            Icons.add_rounded,
            quantity < maxQuantity ? () => setState(() => quantity++) : null,
          ),
        ],
      ),
    );
  }

  // ตัวเลือกแบบกดเลือก 1 อย่าง (วิธีรับสินค้า / วิธีชำระเงิน)
  Widget choiceTile({
    required bool selected,
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? marketColor.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isSubmitting ? null : onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? marketColor : AppColors.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: selected ? marketColor : AppColors.muted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? marketColor : AppColors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildDeliveryOptions() {
    return Column(
      children: [
        for (final option in deliveryOptions())
          choiceTile(
            selected: delivery == option['key'],
            icon:
                findDeliveryMethod(option['key']?.toString() ?? '')?.icon ??
                Icons.local_shipping_outlined,
            title: option['label']?.toString() ?? '',
            subtitle: option['needs_address'] == true
                ? ((option['shipping_fee'] as num?) ?? 0) > 0
                      ? 'ค่าส่ง ${formatPrice(option['shipping_fee'])}'
                      : 'ส่งฟรี'
                : 'ไม่มีค่าส่ง',
            onTap: () => setState(() => selectDelivery(option['key'])),
          ),
      ],
    );
  }

  Widget buildRecipient() {
    return Column(
      children: [
        TextFormField(
          controller: nameController,
          maxLength: 100,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'ชื่อผู้รับ',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            errorText: serverErrors['recipient_name'],
          ),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'กรุณาใส่ชื่อผู้รับ' : null,
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'เบอร์โทรผู้รับ',
            helperText: 'ร้านใช้ติดต่อเรื่องคำสั่งซื้อนี้',
            prefixIcon: const Icon(Icons.phone_outlined),
            errorText: serverErrors['recipient_phone'],
          ),
          validator: (value) {
            final String digits = (value ?? '').replaceAll(
              RegExp(r'[\s\-]'),
              '',
            );

            if (digits.isEmpty) return 'กรุณาใส่เบอร์โทรผู้รับ';

            if (!RegExp(r'^\+?[0-9]{8,19}$').hasMatch(digits)) {
              return 'เบอร์โทรไม่ถูกต้อง';
            }

            return null;
          },
        ),
        if (needsAddress) ...[
          const SizedBox(height: 14),
          TextFormField(
            controller: addressController,
            maxLength: 500,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'ที่อยู่จัดส่ง',
              hintText: 'บ้านเลขที่ ถนน ตำบล อำเภอ จังหวัด รหัสไปรษณีย์',
              alignLabelWithHint: true,
              errorText: serverErrors['address'],
            ),
            validator: (value) => needsAddress && (value ?? '').trim().isEmpty
                ? 'กรุณาใส่ที่อยู่จัดส่ง'
                : null,
          ),
        ],
        const SizedBox(height: 6),
        TextFormField(
          controller: noteController,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: 'ฝากถึงร้าน (ไม่บังคับ)',
            hintText: 'เช่น เวลาที่สะดวกรับของ',
            prefixIcon: const Icon(Icons.sticky_note_2_outlined),
            errorText: serverErrors['note'],
          ),
        ),
      ],
    );
  }

  Widget buildPaymentOptions() {
    final List<Map<String, dynamic>> options = paymentOptions;

    if (delivery == null) {
      return Text(
        'เลือกวิธีรับสินค้าก่อน',
        style: TextStyle(color: AppColors.muted, fontSize: 13),
      );
    }

    return Column(
      children: [
        for (final option in options)
          choiceTile(
            selected: payment == option['key'],
            icon:
                findPaymentMethod(option['key']?.toString() ?? '')?.icon ??
                Icons.payments_outlined,
            title: option['label']?.toString() ?? '',
            subtitle: option['transfer'] == true
                ? 'กดสั่งซื้อแล้วโอนได้เลย แล้วแนบสลิปในคำสั่งซื้อ'
                : 'จ่ายตอนได้รับสินค้า',
            onTap: () => setState(() => payment = option['key']?.toString()),
          ),
      ],
    );
  }

  Widget buildSummary() {
    Widget line(String label, String value, {bool bold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: bold ? AppColors.navy : AppColors.muted,
                  fontSize: bold ? 15 : 13.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: bold ? marketColor : AppColors.navy,
                fontSize: bold ? 18 : 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return card(
      child: Column(
        children: [
          line('ราคาสินค้า × $quantity', formatPrice(unitPrice * quantity)),
          line('ค่าส่ง', shippingFee > 0 ? formatPrice(shippingFee) : 'ไม่มี'),
          const Divider(height: 18),
          line('ยอดรวม', formatPrice(total), bold: true),
        ],
      ),
    );
  }

  Widget buildBody() {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          buildProduct(),
          const SizedBox(height: 12),
          buildQuantity(),
          sectionLabel('วิธีรับสินค้า'),
          buildDeliveryOptions(),
          sectionLabel('ผู้รับสินค้า'),
          buildRecipient(),
          sectionLabel('วิธีชำระเงิน'),
          buildPaymentOptions(),
          const SizedBox(height: 16),
          buildSummary(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.softWarm,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, color: marketColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'เงินโอนเข้าร้านโดยตรง แอปไม่ได้รับเงินแทน '
                    'ควรตรวจสอบร้านและรีวิวก่อนโอนเงิน',
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('สั่งซื้อสินค้า')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadError != null || data == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.remove_shopping_cart_outlined,
                      size: 44,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loadError ?? 'สั่งซื้อสินค้านี้ไม่ได้',
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
          : SafeArea(child: buildBody()),
      bottomNavigationBar: data == null || loadError != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: marketColor,
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: isSubmitting ? null : submit,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.shopping_bag_outlined),
                  label: Text('ยืนยันสั่งซื้อ · ${formatPrice(total)}'),
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    noteController.dispose();

    super.dispose();
  }
}
