import 'package:app_pigeon/app_pigeon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:xocobaby13/core/constants/api_endpoints.dart';
import 'package:xocobaby13/core/extensions/app_navigation_extension.dart';
import 'package:xocobaby13/core/common/widget/loading/app_shimmer.dart';
import 'package:xocobaby13/feature/chat/model/chat_api_mapper.dart';
import 'package:xocobaby13/feature/chat/model/chat_thread_model.dart';
import 'package:xocobaby13/feature/home/controller/live_booking_controller.dart';
import 'package:xocobaby13/feature/chat/presentation/routes/chat_routes.dart';
import 'package:xocobaby13/feature/home/presentation/routes/home_routes.dart';
import 'package:xocobaby13/feature/navigation/presentation/routes/navigation_routes.dart';
import 'package:xocobaby13/core/common/widget/button/loading_buttons.dart';

class HomeDetailsScreen extends StatefulWidget {
  final bool isBooked;
  final bool showBookingButton;
  final double? lat;
  final double? lng;
  final double? distanceKm;
  final String? spotId;
  final String? bookingId;
  final String? paymentId;
  final String? bookingDateLabel;
  final String? bookingTimeRange;
  final String? bookingStatus;
  final int? bookingPrice;

  const HomeDetailsScreen({
    super.key,
    this.isBooked = false,
    this.showBookingButton = true,
    this.lat,
    this.lng,
    this.distanceKm,
    this.spotId,
    this.bookingId,
    this.paymentId,
    this.bookingDateLabel,
    this.bookingTimeRange,
    this.bookingStatus,
    this.bookingPrice,
  });

  @override
  State<HomeDetailsScreen> createState() => _HomeDetailsScreenState();
}

class _HomeDetailsScreenState extends State<HomeDetailsScreen> {
  late bool _isBooked;
  String? _bookingId;
  String? _paymentId;
  String? _bookingDateLabel;
  String? _bookingTimeRange;
  int? _bookingPrice;
  bool _isLoadingSpot = false;
  String? _spotError;
  Map<String, dynamic>? _spot;
  bool _isBooking = false;
  bool _isCreatingChat = false;
  int _selectedPhotoIndex = 0;
  static const List<String> _fallbackPhotos = <String>[
    'https://images.unsplash.com/photo-1482192596544-9eb780fc7f66?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=400&q=80',
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=400&q=80',
  ];
  static const List<String> _fallbackTags = <String>[
    'Dock',
    'Kayak',
    'Rods',
    'Catfish',
    'Life Jacket',
    'License',
    'Guide',
    'Parking',
  ];
  static const List<String> _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _isBooked = widget.isBooked;
    _bookingId = widget.bookingId;
    _paymentId = widget.paymentId;
    _bookingDateLabel = widget.bookingDateLabel;
    _bookingTimeRange = widget.bookingTimeRange;
    _bookingPrice = widget.bookingPrice;
    _loadSpot();
    _loadExistingBooking();
  }

  String _formatBookingDate(DateTime value) {
    final String year = value.year.toString().padLeft(4, '0');
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _createBooking() async {
    if (_isBooking) return;
    final String? spotId = widget.spotId ?? _spot?['_id']?.toString();
    if (spotId == null || spotId.isEmpty) {
      _showMessage(context, 'Spot id is missing');
      return;
    }
    setState(() => _isBooking = true);
    try {
      final DateTime bookingDate = DateTime.now().add(const Duration(days: 1));
      final response = await Get.find<AuthorizedPigeon>().post(
        ApiEndpoints.createBooking,
        data: <String, dynamic>{
          'spotId': spotId,
          'date': _formatBookingDate(bookingDate),
          'slot': <String, String>{'start': '7:00 AM', 'end': '9:00 AM'},
        },
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final String bookingId = _extractBookingId(responseBody);
      if (bookingId.isEmpty) {
        if (!mounted) return;
        _showMessage(context, 'Booking id missing in response');
        return;
      }
      final double amount = _extractBookingAmount(responseBody);
      final String paymentPath =
          '${HomeRouteNames.payment}?bookingId=${Uri.encodeComponent(bookingId)}&amount=${Uri.encodeComponent(amount.toStringAsFixed(2))}';
      if (!mounted) return;
      final bool? paid = await context.push<bool>(paymentPath);
      if (!mounted) return;
      if (paid == true) {
        setState(() => _isBooked = true);
        await _showBookingSuccessDialog();
        if (!mounted) return;
        context.go(NavigationRouteNames.main);
      }
    } on DioException catch (e) {
      final dynamic responseData = e.response?.data;
      final String message =
          responseData is Map && responseData['message'] != null
          ? responseData['message'].toString()
          : 'Failed to create booking';
      if (!mounted) return;
      _showMessage(context, message);
    } catch (_) {
      if (!mounted) return;
      _showMessage(context, 'Failed to create booking');
    } finally {
      if (mounted) {
        setState(() => _isBooking = false);
      }
    }
  }

  String _extractBookingId(Map<String, dynamic> responseBody) {
    final dynamic data = responseBody['data'];
    if (data is Map) {
      final String bookingId =
          data['_id']?.toString().trim() ?? data['id']?.toString().trim() ?? '';
      if (bookingId.isNotEmpty) return bookingId;
    }
    return '';
  }

  double _extractBookingAmount(Map<String, dynamic> responseBody) {
    final dynamic data = responseBody['data'];
    if (data is Map) {
      final double amount = _readDouble(data['totalAmount']);
      if (amount > 0) return amount;
    }
    final double spotPrice = _readDouble(_spot?['price']);
    return spotPrice > 0 ? spotPrice : 0;
  }

  Future<void> _showBookingSuccessDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Payment Successful'),
          content: const Text(
            'Your booking is confirmed. Enjoy your fishing trip!',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startChat() async {
    if (_isCreatingChat) return;
    final String ownerId = _readString(_spot?['owner']?['_id']);
    if (ownerId.isEmpty) {
      _showMessage(context, 'Spot owner not found');
      return;
    }
    setState(() => _isCreatingChat = true);
    try {
      final String currentUserId = await _resolveCurrentUserId();
      if (!mounted) {
        return;
      }
      if (currentUserId.isNotEmpty && currentUserId == ownerId) {
        _showMessage(context, "You can't chat with yourself");
        return;
      }
      final response = await Get.find<AuthorizedPigeon>().post(
        ApiEndpoints.createChat,
        data: <String, dynamic>{'fisherId': ownerId},
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      final Map<String, dynamic> chat = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};
      if (chat.isEmpty) {
        throw Exception('Empty chat');
      }
      final ChatThreadModel thread = ChatApiMapper.threadFromChatListItem(
        chat,
        currentUserId,
      );
      if (!mounted) return;
      await context.push(ChatRouteNames.detail, extra: thread);
    } catch (e) {
      if (mounted) {
        _showMessage(context, 'Failed to start chat');
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingChat = false);
      }
    }
  }

  Future<void> _loadSpot() async {
    final String? spotId = widget.spotId;
    if (spotId == null || spotId.isEmpty) return;
    if (_isLoadingSpot) return;
    setState(() {
      _isLoadingSpot = true;
      _spotError = null;
    });
    try {
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.spotById(spotId),
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      if (data is Map) {
        _spot = Map<String, dynamic>.from(data);
      }
      if (!mounted) return;
      setState(() {
        _isLoadingSpot = false;
        _selectedPhotoIndex = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _spotError = 'Failed to load spot details';
        _isLoadingSpot = false;
      });
    }
  }

  Future<void> _loadExistingBooking() async {
    final String spotId = _readString(widget.spotId);
    if (spotId.isEmpty) {
      return;
    }
    try {
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.getMyBookings,
        queryParameters: const <String, dynamic>{'limit': 100},
      );
      final Map<String, dynamic> responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final dynamic data = responseBody['data'];
      if (data is! List) {
        return;
      }

      Map<String, dynamic>? matchedBooking;
      for (final dynamic item in data) {
        if (item is! Map) {
          continue;
        }
        final Map<String, dynamic> booking = Map<String, dynamic>.from(item);
        final String bookingSpotId = _readString(
          booking['spot'] is Map ? booking['spot']['_id'] : null,
        );
        final String status = _readString(booking['status']);
        final String paymentId = _readObjectId(booking['paymentId']) ?? '';
        final String paymentStatus = _readString(booking['paymentStatus']);
        final bool isRefunded = paymentStatus.toLowerCase() == 'refunded';
        final bool isCanceled = status.toLowerCase() == 'cancelled';

        if (bookingSpotId != spotId || isCanceled || isRefunded) {
          continue;
        }
        if (paymentId.isEmpty) {
          continue;
        }
        matchedBooking = booking;
        break;
      }

      if (!mounted || matchedBooking == null) {
        return;
      }

      final Map<String, dynamic> booking = matchedBooking;
      final Map<String, dynamic> slot = booking['slot'] is Map
          ? Map<String, dynamic>.from(booking['slot'])
          : <String, dynamic>{};

      setState(() {
        _isBooked = true;
        _bookingId = _readString(booking['_id']);
        _paymentId = _readObjectId(booking['paymentId']);
        _bookingDateLabel = _formatLongDate(booking['date']?.toString());
        _bookingTimeRange = _formatBookingTimeRange(slot);
        _bookingPrice = _readInt(
          booking['spot'] is Map
              ? booking['spot']['price'] ?? booking['totalAmount']
              : booking['totalAmount'],
        );
      });
    } catch (_) {
      // Keep the current button state if this lookup fails.
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Future<String> _resolveCurrentUserId() async {
    try {
      final authRecord = await Get.find<AuthorizedPigeon>()
          .getCurrentAuthRecord();
      final Map<String, dynamic> data = authRecord?.data is Map
          ? Map<String, dynamic>.from(authRecord!.data as Map)
          : <String, dynamic>{};
      final dynamic raw = authRecord?.toJson();
      final Map<String, dynamic> record = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      return _pickFirstString(<dynamic>[
        data['id'],
        data['_id'],
        data['userId'],
        record['uid'],
        record['userId'],
        record['user_id'],
        record['id'],
        record['_id'],
      ]);
    } catch (_) {
      return '';
    }
  }

  String _pickFirstString(List<dynamic> values) {
    for (final dynamic value in values) {
      final String text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  double _zoomForDistance(double? distanceKm) {
    if (distanceKm == null) return 3.6;
    if (distanceKm <= 5) return 12;
    if (distanceKm <= 15) return 10;
    if (distanceKm <= 30) return 8;
    if (distanceKm <= 60) return 6;
    return 4.5;
  }

  String _readString(dynamic value, {String fallback = ''}) {
    final String text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  double _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  String _formatLocation(dynamic location) {
    if (location is Map) {
      final String address = location['address']?.toString() ?? '';
      final String city = location['city']?.toString() ?? '';
      final String country = location['country']?.toString() ?? '';
      final parts = <String>[
        if (address.isNotEmpty) address,
        if (city.isNotEmpty) city,
        if (country.isNotEmpty) country,
      ];
      if (parts.isNotEmpty) return parts.join(', ');
    }
    return 'Unknown location';
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return 'FEB 10';
    final DateTime? dateTime = DateTime.tryParse(value);
    if (dateTime == null) return 'FEB 10';
    final String month = _monthNames[dateTime.month - 1].toUpperCase();
    return '$month ${dateTime.day}';
  }

  String _formatLongDate(String? value) {
    if (value == null || value.isEmpty) return 'Feb 10, 2026';
    final DateTime? dateTime = DateTime.tryParse(value);
    if (dateTime == null) return 'Feb 10, 2026';
    final String month = _monthNames[dateTime.month - 1];
    final String day = dateTime.day.toString().padLeft(2, '0');
    return '$month $day, ${dateTime.year}';
  }

  String _formatBookingTimeRange(Map<String, dynamic> slot) {
    final String start = _readString(slot['start']);
    final String end = _readString(slot['end']);
    if (start.isEmpty || end.isEmpty) {
      return '';
    }
    return '${_formatTime(start)} - ${_formatTime(end)}';
  }

  String _firstAvailabilityLabel(dynamic availability) {
    if (availability is! List || availability.isEmpty) {
      return 'Flexible';
    }
    final dynamic firstAvailability = availability.first;
    if (firstAvailability is! Map) {
      return 'Flexible';
    }
    final dynamic slots = firstAvailability['slots'];
    if (slots is! List || slots.isEmpty) {
      return 'Flexible';
    }
    final dynamic firstSlot = slots.first;
    if (firstSlot is! Map) {
      return 'Flexible';
    }
    final String start = _readString(firstSlot['start']);
    final String end = _readString(firstSlot['end']);
    if (start.isEmpty || end.isEmpty) {
      return 'Flexible';
    }
    return '$start - $end';
  }

  String _formatTime(String value) {
    final List<String> parts = value.split(':');
    if (parts.length < 2) {
      return value;
    }
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return value;
    }
    final int hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final String suffix = hour >= 12 ? 'PM' : 'AM';
    final String minuteText = minute.toString().padLeft(2, '0');
    return '$hour12:$minuteText $suffix';
  }

  String? _readObjectId(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Map) {
      final String nestedId =
          value['_id']?.toString().trim() ??
          value['id']?.toString().trim() ??
          '';
      return nestedId.isEmpty ? null : nestedId;
    }
    final String text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<String> _readImages(dynamic images) {
    if (images is List) {
      return images
          .map((dynamic item) {
            if (item is String) return item;
            if (item is Map && item['url'] != null) {
              return item['url'].toString();
            }
            return '';
          })
          .where((String url) => url.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  List<String> _readTags(dynamic value) {
    if (value is List) {
      return value
          .map((dynamic item) => item?.toString() ?? '')
          .where((String item) => item.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  LatLng? _readLatLng(dynamic location) {
    if (location is Map) {
      final point = location['point'];
      if (point is Map && point['coordinates'] is List) {
        final List coords = point['coordinates'] as List;
        if (coords.length >= 2) {
          final double lng = _readDouble(coords[0]);
          final double lat = _readDouble(coords[1]);
          return LatLng(lat, lng);
        }
      }
    }
    return null;
  }

  void _openCancellationSheet() {
    final BuildContext parentContext = context;
    String? selectedReason;
    bool isSubmitting = false;
    final List<String> previewPhotos = _readImages(_spot?['images']);
    final String previewImage = previewPhotos.isNotEmpty
        ? previewPhotos.first
        : _fallbackPhotos.first;
    final String previewTitle = _readString(
      _spot?['title'],
      fallback: 'Crystal Lake Sanctuary',
    );
    final String previewTimeRange = _readString(
      _bookingTimeRange,
      fallback: '7:00 AM - 5:00 PM',
    );
    final String previewDate = _readString(
      _bookingDateLabel,
      fallback: _formatLongDate(_spot?['createdAt']?.toString()),
    );
    final String previewLocation = _formatLocation(_spot?['location']);
    final int previewPrice = _bookingPrice ?? _readInt(_spot?['price']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9E3EE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const Center(
                      child: Text(
                        'Cancellation',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE23A3A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1787CF)),
                      ),
                      child: Row(
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              previewImage,
                              width: 72,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 72,
                                    height: 56,
                                    color: const Color(0xFFE2E8F1),
                                    child: const Icon(Icons.photo, size: 20),
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  previewTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1D2A36),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  previewTimeRange,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: Color(0xFF6A7B8C),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${previewLocation.isEmpty ? 'Unknown location' : previewLocation}   •   $previewDate',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: Color(0xFF6A7B8C),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: <Widget>[
                              const CircleAvatar(
                                radius: 12,
                                backgroundImage: NetworkImage(
                                  'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=200&q=80',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '\$$previewPrice',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E7CC8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Reason for Cancellation',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        hintText: 'Select a reason',
                        hintStyle: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6A7B8C),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFD2DEE9),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF1787CF),
                          ),
                        ),
                      ),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem(
                          value: 'Bad Weather',
                          child: Text('Bad Weather'),
                        ),
                        DropdownMenuItem(
                          value: 'Wrong Spot',
                          child: Text('Wrong Spot'),
                        ),
                        DropdownMenuItem(
                          value: 'Emergency',
                          child: Text('Emergency'),
                        ),
                        DropdownMenuItem(
                          value: 'Others',
                          child: Text('Others'),
                        ),
                      ],
                      onChanged: (String? value) {
                        setSheetState(() => selectedReason = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: AppElevatedButton(
                        onPressed: selectedReason == null || isSubmitting
                            ? null
                            : () async {
                                setSheetState(() => isSubmitting = true);
                                final bool success = await _requestRefund(
                                  selectedReason!,
                                );
                                if (!mounted) {
                                  return;
                                }
                                setSheetState(() => isSubmitting = false);
                                if (!success) {
                                  return;
                                }
                                if (!sheetContext.mounted) {
                                  return;
                                }
                                Navigator.of(sheetContext).pop();
                                if (!parentContext.mounted) {
                                  return;
                                }
                                await parentContext.push(
                                  HomeRouteNames.refundRequest,
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1787CF),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Request For Refund',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _requestRefund(String reason) async {
    final String paymentId = _readString(_paymentId);
    if (paymentId.isEmpty) {
      _showMessage(context, 'Payment id is missing for this booking');
      return false;
    }

    try {
      final response = await _sendRefundRequest(
        paymentId: paymentId,
        reason: reason,
      );
      final Map<String, dynamic> responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final String message = _readString(
        responseBody['message'],
        fallback: 'Refund processed successfully',
      );
      if (!mounted) {
        return false;
      }
      _showMessage(context, message);
      setState(() => _isBooked = false);
      LiveBookingController.instance().loadLiveBookings();
      return true;
    } on DioException catch (e) {
      final int statusCode = e.response?.statusCode ?? 0;
      if (statusCode == 400) {
        final bool confirmed = await _confirmBookingPayment();
        if (confirmed) {
          try {
            final retryResponse = await _sendRefundRequest(
              paymentId: paymentId,
              reason: reason,
            );
            final Map<String, dynamic> retryBody = retryResponse.data is Map
                ? Map<String, dynamic>.from(retryResponse.data as Map)
                : <String, dynamic>{};
            final String retryMessage = _readString(
              retryBody['message'],
              fallback: 'Refund processed successfully',
            );
            if (!mounted) {
              return false;
            }
            _showMessage(context, retryMessage);
            setState(() => _isBooked = false);
            LiveBookingController.instance().loadLiveBookings();
            return true;
          } on DioException catch (retryError) {
            final dynamic retryData = retryError.response?.data;
            final String retryMessage =
                retryData is Map && retryData['message'] != null
                ? retryData['message'].toString()
                : 'Failed to request refund';
            if (!mounted) {
              return false;
            }
            _showMessage(context, retryMessage);
            return false;
          }
        }
      }
      final dynamic responseData = e.response?.data;
      final String message =
          responseData is Map && responseData['message'] != null
          ? responseData['message'].toString()
          : 'Failed to request refund';
      if (!mounted) {
        return false;
      }
      _showMessage(context, message);
      return false;
    } catch (_) {
      if (!mounted) {
        return false;
      }
      _showMessage(context, 'Failed to request refund');
      return false;
    }
  }

  Future<dynamic> _sendRefundRequest({
    required String paymentId,
    required String reason,
  }) {
    return Get.find<AuthorizedPigeon>().post(
      ApiEndpoints.paymentRefund(paymentId),
      data: <String, dynamic>{'reason': reason},
    );
  }

  Future<bool> _confirmBookingPayment() async {
    final String bookingId = _readString(_bookingId);
    if (bookingId.isEmpty) {
      return false;
    }

    try {
      final response = await Get.find<AuthorizedPigeon>().post(
        ApiEndpoints.paymentConfirm,
        data: <String, dynamic>{'bookingId': bookingId},
      );
      final Map<String, dynamic> responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final dynamic data = responseBody['data'];
      if (data is Map) {
        final String confirmedPaymentId = _readObjectId(data['payment']) ?? '';
        if (confirmedPaymentId.isNotEmpty) {
          _paymentId = confirmedPaymentId;
        }
        if (data['payment'] is Map) {
          final Map<String, dynamic> payment = Map<String, dynamic>.from(
            data['payment'] as Map,
          );
          final String confirmedPaymentId =
              _readObjectId(payment['_id']) ??
              _readObjectId(payment['id']) ??
              '';
          if (confirmedPaymentId.isNotEmpty) {
            _paymentId = confirmedPaymentId;
          }
        }
        final bool isPaid = data['paid'] == true;
        if (isPaid) {
          LiveBookingController.instance().loadLiveBookings();
        }
        return isPaid;
      }
      return false;
    } on DioException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? spot = _spot;
    final List<String> photos = _readImages(spot?['images']);
    final List<String> galleryPhotos = photos.isEmpty
        ? _fallbackPhotos
        : photos;
    final int safePhotoIndex = _selectedPhotoIndex.clamp(
      0,
      galleryPhotos.isEmpty ? 0 : galleryPhotos.length - 1,
    );
    final String title = _readString(
      spot?['title'],
      fallback: 'Crystal Lake Sanctuary',
    );
    final String description = _readString(
      spot?['description'],
      fallback: 'No description has been added for this spot yet.',
    );
    final int price = _readInt(spot?['price']);
    final double rating = _readDouble(spot?['ratingAvg']);
    final int reviews = _readInt(spot?['ratingCount']);
    final String dateLabel = _formatDate(spot?['createdAt']?.toString());
    final List<String> facilities = _readTags(
      spot?['facilities'] ?? spot?['features'],
    );
    final List<String> restrictions = _readTags(spot?['restrictions']);
    final String hostName = _readString(
      spot?['owner']?['fullName'],
      fallback: 'John Mitchell',
    );
    final String hostAvatar = _readString(spot?['owner']?['avatar']?['url']);
    final String locationLabel = _formatLocation(spot?['location']);
    final LatLng? spotLatLng = _readLatLng(spot?['location']);
    final LatLng mapCenter =
        spotLatLng ??
        ((widget.lat != null && widget.lng != null)
            ? LatLng(widget.lat!, widget.lng!)
            : const LatLng(39.8283, -98.5795));
    final double mapZoom = _zoomForDistance(widget.distanceKm);
    final int bookedSlots = _readInt(spot?['bookedSlots']);
    final int availableSlots = _readInt(spot?['availableSlots']);
    final int totalSlots = _readInt(spot?['totalSlots']);
    final String timeLabel = _readString(
      _bookingTimeRange,
      fallback: _firstAvailabilityLabel(spot?['availability']),
    );

    if (_isLoadingSpot && spot == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFF2F9FF),
        body: SafeArea(child: _HomeDetailsSkeleton()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F9FF),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        GestureDetector(
                          onTap: () => context.safePop(),
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Icon(
                                CupertinoIcons.back,
                                size: 20,
                                color: Color(0xFF1D2A36),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'View Details',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1D2A36),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_spotError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          _spotError!,
                          style: const TextStyle(
                            color: Color(0xFFE23A3A),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        galleryPhotos[safePhotoIndex],
                        height: 310,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 250,
                          color: const Color(0xFFE2E8F1),
                          child: const Icon(Icons.photo, size: 40),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'More Photos',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 62,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: galleryPhotos.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (BuildContext context, int index) {
                          final bool isSelected = index == safePhotoIndex;
                          return Stack(
                            children: <Widget>[
                              GestureDetector(
                                onTap: () {
                                  setState(() => _selectedPhotoIndex = index);
                                },
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    galleryPhotos[index],
                                    width: 62,
                                    height: 62,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              width: 62,
                                              height: 62,
                                              color: const Color(0xFFE2E8F1),
                                              child: const Icon(
                                                Icons.photo,
                                                size: 24,
                                              ),
                                            ),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFF1787CF),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D2A36),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE7F2FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: RichText(
                            text: TextSpan(
                              children: <TextSpan>[
                                TextSpan(
                                  text: price > 0 ? '\$$price' : r'$120',
                                  style: const TextStyle(
                                    color: Color(0xFF1E7CC8),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                                const TextSpan(
                                  text: '/day',
                                  style: TextStyle(
                                    color: Color(0xFF1D2A36),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(
                          CupertinoIcons.location_solid,
                          size: 13,
                          color: Color(0xFF3A4A5A),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            locationLabel,
                            // maxLines: 3,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF3A4A5A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          CupertinoIcons.calendar,
                          size: 13,
                          color: Color(0xFF3A4A5A),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatLongDate(spot?['createdAt']?.toString()),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF3A4A5A),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const <Widget>[
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _DetailStatLabel(label: 'Rating'),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: _DetailStatLabel(label: 'Time'),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _DetailStatLabel(label: 'Date'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              const Icon(
                                CupertinoIcons.star_fill,
                                size: 12,
                                color: Color(0xFFF2B01E),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                rating > 0 ? rating.toStringAsFixed(1) : '0.0',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1D2A36),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Text(
                            timeLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D2A36),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            dateLabel,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D2A36),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: const <Widget>[
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _DetailStatLabel(label: 'Booked Slots'),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _DetailStatLabel(label: 'Available Slots'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            totalSlots > 0
                                ? '$bookedSlots/$totalSlots Slots'
                                : '$bookedSlots Slots',
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1D2A36),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            totalSlots > 0
                                ? '$availableSlots/$totalSlots Slots'
                                : '$availableSlots Slots',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E7CC8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Facilities',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _TagWrap(
                      tags: facilities.isEmpty ? _fallbackTags : facilities,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Restriction',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _TagWrap(
                      tags: restrictions.isEmpty
                          ? const <String>['No restrictions listed']
                          : restrictions,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Description',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: const TextStyle(
                        height: 1.4,
                        fontSize: 11,
                        color: Color(0xFF3A4A5A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Host Information',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 17,
                          backgroundImage: hostAvatar.isNotEmpty
                              ? NetworkImage(hostAvatar)
                              : null,
                          backgroundColor: const Color(0xFFE2E8F1),
                          child: hostAvatar.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 18,
                                  color: Color(0xFF6A7B8C),
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                hostName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1D2A36),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: <Widget>[
                                  const Icon(
                                    CupertinoIcons.star_fill,
                                    size: 11,
                                    color: Color(0xFFF2B01E),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${rating.toStringAsFixed(1)} ($reviews Reviews)',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6A7B8C),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: 32,
                          child: AppElevatedButton(
                            onPressed: _startChat,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1787CF),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9),
                              ),
                            ),
                            child: const Text(
                              'Start Chat',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Location',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      locationLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6A7B8C),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Stack(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            height: 240,
                            width: double.infinity,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: mapCenter,
                                initialZoom: mapZoom,
                                interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none,
                                ),
                                onTap: (tapPos, _) {
                                  if (spotLatLng == null) {
                                    _showMessage(
                                      context,
                                      'This spot does not have a saved map location yet',
                                    );
                                    return;
                                  }
                                  final Uri directionUri = Uri(
                                    path: HomeRouteNames.direction,
                                    queryParameters: <String, String>{
                                      'title': title,
                                      'address': locationLabel,
                                      'lat': spotLatLng.latitude.toString(),
                                      'lng': spotLatLng.longitude.toString(),
                                    },
                                  );
                                  context.push(directionUri.toString());
                                },
                              ),
                              children: <Widget>[
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName:
                                      'com.example.xocobaby13',
                                ),
                                MarkerLayer(
                                  markers: <Marker>[
                                    Marker(
                                      point: mapCenter,
                                      width: 36,
                                      height: 46,
                                      child: const Icon(
                                        Icons.location_pin,
                                        color: Color(0xFFE23A3A),
                                        size: 40,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: GestureDetector(
                            onTap: () {
                              if (spotLatLng == null) {
                                _showMessage(
                                  context,
                                  'This spot does not have a saved map location yet',
                                );
                                return;
                              }
                              final Uri directionUri = Uri(
                                path: HomeRouteNames.direction,
                                queryParameters: <String, String>{
                                  'title': title,
                                  'address': locationLabel,
                                  'lat': spotLatLng.latitude.toString(),
                                  'lng': spotLatLng.longitude.toString(),
                                },
                              );
                              context.push(directionUri.toString());
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0x22000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: const <Widget>[
                                  Text(
                                    'Get Direction',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1D2A36),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Icon(
                                    CupertinoIcons.location_solid,
                                    color: Color(0xFF1E7CC8),
                                    size: 13,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (widget.showBookingButton)
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  color: const Color(0xFFF2F9FF),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: AppElevatedButton(
                      onPressed: _isBooking
                          ? null
                          : _isBooked
                          ? _openCancellationSheet
                          : _createBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1787CF),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isBooking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _isBooked ? 'Cancel & Refund' : 'Book Now',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HomeDetailsSkeleton extends StatelessWidget {
  const _HomeDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 112),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const <Widget>[
          Row(
            children: <Widget>[
              AppShimmerBox(width: 24, height: 24, shape: BoxShape.circle),
              SizedBox(width: 10),
              AppShimmerBox(width: 100, height: 16),
            ],
          ),
          SizedBox(height: 14),
          AppShimmerBox(height: 310, width: double.infinity),
          SizedBox(height: 14),
          AppShimmerBox(width: 110, height: 16),
          SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: AppShimmerBox(height: 62)),
              SizedBox(width: 10),
              Expanded(child: AppShimmerBox(height: 62)),
              SizedBox(width: 10),
              Expanded(child: AppShimmerBox(height: 62)),
            ],
          ),
          SizedBox(height: 18),
          AppShimmerBox(width: 220, height: 26),
          SizedBox(height: 10),
          AppShimmerBox(width: 180, height: 14),
          SizedBox(height: 18),
          AppShimmerBox(width: double.infinity, height: 120),
          SizedBox(height: 18),
          AppShimmerBox(width: double.infinity, height: 220),
        ],
      ),
    );
  }
}

class _DetailStatLabel extends StatelessWidget {
  final String label;

  const _DetailStatLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 10,
        color: Color(0xFF6A7B8C),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _TagWrap extends StatelessWidget {
  final List<String> tags;

  const _TagWrap({required this.tags});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags
          .map(
            (String tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F2FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1D2A36),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
