import 'dart:async';
import 'dart:ui';

import 'package:app_pigeon/app_pigeon.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:xocobaby13/core/constants/api_endpoints.dart';
import 'package:go_router/go_router.dart';
import 'package:xocobaby13/feature/home/controller/live_booking_controller.dart';
import 'package:xocobaby13/feature/home/presentation/routes/home_routes.dart';
import 'package:xocobaby13/feature/notification/presentation/routes/notification_routes.dart';
import 'package:xocobaby13/core/common/widget/button/loading_buttons.dart';
import 'package:xocobaby13/core/common/widget/loading/app_shimmer.dart';
import 'package:xocobaby13/feature/profile/controller/profile_controller.dart';
import 'package:xocobaby13/feature/profile/model/user_profile_data_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _liveController;
  late final LiveBookingController _liveBookingController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  Timer? _searchDebounce;
  bool _isLoadingNearby = false;
  String? _nearbyError;
  List<_PopularPlace> _popularPlaces = const <_PopularPlace>[];
  bool _isLoadingRecommended = false;
  String? _recommendedError;
  List<_RecommendedPlace> _recommendedPlaces = const <_RecommendedPlace>[];
  List<_HomeSearchResult> _searchResults = const <_HomeSearchResult>[];
  bool _isSearching = false;
  bool _showSearchResults = false;
  String? _searchError;
  String _searchQuery = '';
  int _searchRequestId = 0;
  bool _isLoadingUnread = false;
  int _unreadCount = 0;
  static const double _defaultNearbyLat = 23.8103;
  static const double _defaultNearbyLng = 90.4125;
  static const double _defaultNearbyDistanceKm = 100;
  double _nearbyLat = _defaultNearbyLat;
  double _nearbyLng = _defaultNearbyLng;
  final double _nearbyDistanceKm = _defaultNearbyDistanceKm;
  static const List<String> _defaultAttendees = <String>[
    'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=200&q=80',
    'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=200&q=80',
    'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=200&q=80',
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

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _liveController = PageController();
    _liveBookingController = LiveBookingController.instance();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode()
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _showSearchResults =
              _searchFocusNode.hasFocus && _searchQuery.isNotEmpty;
        });
      });
    _liveBookingController.loadLiveBookings();
    _resolveNearbyLocationAndLoad();
    _loadRecommendedSpots();
    _loadUnreadCount();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _liveController.dispose();
    super.dispose();
  }

  void _handleLiveStatusTap(int index) {
    _liveBookingController.toggleArrivalAt(index);
  }

  void _onSearchChanged(String value) {
    final String nextQuery = value.trim();
    _searchDebounce?.cancel();

    if (nextQuery.isEmpty) {
      _searchRequestId++;
      setState(() {
        _searchQuery = '';
        _searchError = null;
        _isSearching = false;
        _showSearchResults = false;
        _searchResults = const <_HomeSearchResult>[];
      });
      return;
    }

    setState(() {
      _searchQuery = nextQuery;
      _showSearchResults = _searchFocusNode.hasFocus;
    });

    _searchDebounce = Timer(const Duration(milliseconds: 350), _searchSpots);
  }

  Future<void> _searchSpots() async {
    final String query = _searchQuery.trim();
    if (query.isEmpty) return;

    final int requestId = ++_searchRequestId;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _showSearchResults = true;
    });

    try {
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.searchSpots,
        queryParameters: <String, dynamic>{'q': query, 'limit': 6},
      );
      if (!mounted || requestId != _searchRequestId) return;

      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final dynamic data = responseBody['data'];
      final List<_HomeSearchResult> nextResults = <_HomeSearchResult>[];

      if (data is List) {
        for (final dynamic item in data) {
          if (item is Map) {
            nextResults.add(
              _mapSpotToHomeSearchResult(Map<String, dynamic>.from(item)),
            );
          }
        }
      }

      setState(() {
        _searchResults = nextResults;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchError = 'Failed to fetch search results';
        _isSearching = false;
      });
    }
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchRequestId++;
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = '';
      _searchError = null;
      _isSearching = false;
      _showSearchResults = false;
      _searchResults = const <_HomeSearchResult>[];
    });
  }

  Future<void> _openSearchResult(_HomeSearchResult result) async {
    final query = <String, String>{
      'lat': result.lat.toString(),
      'lng': result.lng.toString(),
      'distanceKm': _nearbyDistanceKm.toString(),
    };
    if (result.id.isNotEmpty) {
      query['id'] = result.id;
    }
    final detailsUri = Uri(
      path: HomeRouteNames.details,
      queryParameters: query,
    );
    _searchFocusNode.unfocus();
    await context.push(detailsUri.toString());
    if (!mounted) return;
    _clearSearch();
  }

  Future<void> _resolveNearbyLocationAndLoad() async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _loadNearbySpots();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _loadNearbySpots();
        return;
      }

      final Position position = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 8),
      );
      if (!mounted) return;
      setState(() {
        _nearbyLat = position.latitude;
        _nearbyLng = position.longitude;
      });
    } catch (_) {
      // Fall back to default coordinates when location is unavailable or timed out.
    }

    await _loadNearbySpots();
  }

  Future<void> _loadNearbySpots() async {
    if (_isLoadingNearby) return;
    setState(() {
      _isLoadingNearby = true;
      _nearbyError = null;
    });
    try {
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.nearbySpots,
        queryParameters: <String, dynamic>{
          'lat': _nearbyLat,
          'lng': _nearbyLng,
          'distanceKm': _nearbyDistanceKm,
        },
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      final List<_PopularPlace> spots = <_PopularPlace>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            spots.add(_mapSpotToPopularPlace(Map<String, dynamic>.from(item)));
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _popularPlaces = spots;
        _isLoadingNearby = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nearbyError = 'Failed to load nearby spots';
        _isLoadingNearby = false;
      });
    }
  }

  Future<void> _loadRecommendedSpots() async {
    if (_isLoadingRecommended) return;
    setState(() {
      _isLoadingRecommended = true;
      _recommendedError = null;
    });
    try {
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.recommendedSpots,
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      final List<_RecommendedPlace> spots = <_RecommendedPlace>[];
      if (data is List) {
        for (final item in data) {
          if (item is Map) {
            spots.add(
              _mapSpotToRecommendedPlace(Map<String, dynamic>.from(item)),
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _recommendedPlaces = spots;
        _isLoadingRecommended = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recommendedError = 'Failed to load recommended spots';
        _isLoadingRecommended = false;
      });
    }
  }

  Future<void> _loadUnreadCount() async {
    if (_isLoadingUnread) return;
    setState(() => _isLoadingUnread = true);
    try {
      final response = await Get.find<AuthorizedPigeon>().get(
        ApiEndpoints.getUnreadNotificationCount,
      );
      final responseBody = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final data = responseBody['data'];
      int count = 0;
      if (data is Map) {
        count = _readInt(data['unreadCount']);
      }
      if (!mounted) return;
      setState(() {
        _unreadCount = count;
        _isLoadingUnread = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingUnread = false);
    }
  }

  _PopularPlace _mapSpotToPopularPlace(Map<String, dynamic> spot) {
    final String title = spot['title']?.toString().trim().isNotEmpty == true
        ? spot['title'].toString()
        : 'Untitled Spot';
    final String location = _formatLocation(spot['location']);
    final String date = _formatDate(spot['createdAt']?.toString());
    final double rating = _readDouble(spot['ratingAvg']);
    final int reviews = _readInt(spot['ratingCount']);
    final int pricePerDay = _readInt(spot['price']);
    final String imageUrl = _pickImageUrl(spot['images']);
    final List<String> tags = _readStringList(
      spot['facilities'] ?? spot['features'],
    );
    final List<double> coords = _readCoordinates(spot['location']);
    final String? spotId = spot['_id']?.toString();

    return _PopularPlace(
      title: title,
      location: location,
      date: date,
      rating: rating,
      reviews: reviews,
      timeRange: 'All day',
      pricePerDay: pricePerDay,
      imageUrl: imageUrl.isEmpty
          ? 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1200&q=80'
          : imageUrl,
      tags: tags.isEmpty ? const <String>['Popular'] : tags,
      attendees: _defaultAttendees,
      attendeesLabel: 'Nearby anglers',
      attendeesSubtitle: 'are going in this location',
      lat: coords.isNotEmpty ? coords[0] : null,
      lng: coords.length > 1 ? coords[1] : null,
      id: spotId,
    );
  }

  _RecommendedPlace _mapSpotToRecommendedPlace(Map<String, dynamic> spot) {
    final String title = spot['title']?.toString().trim().isNotEmpty == true
        ? spot['title'].toString()
        : 'Untitled Spot';
    final String location = _formatLocation(spot['location']);
    final String date = _formatDate(spot['createdAt']?.toString());
    final double rating = _readDouble(spot['ratingAvg']);
    final int reviews = _readInt(spot['ratingCount']);
    final String imageUrl = _pickImageUrl(spot['images']);
    final List<double> coords = _readCoordinates(spot['location']);
    final String? spotId = spot['_id']?.toString();

    return _RecommendedPlace(
      title: title,
      location: location,
      date: date,
      rating: rating,
      reviews: reviews,
      timeRange: 'All day',
      imageUrl: imageUrl.isEmpty
          ? 'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=600&q=80'
          : imageUrl,
      id: spotId,
      lat: coords.isNotEmpty ? coords[0] : null,
      lng: coords.length > 1 ? coords[1] : null,
    );
  }

  _HomeSearchResult _mapSpotToHomeSearchResult(Map<String, dynamic> spot) {
    final List<double> coords = _readCoordinates(spot['location']);

    return _HomeSearchResult(
      id: spot['_id']?.toString() ?? '',
      title: spot['title']?.toString().trim().isNotEmpty == true
          ? spot['title'].toString()
          : 'Untitled Spot',
      location: _formatLocation(spot['location']),
      price: _readInt(spot['price']),
      lat: coords.isNotEmpty ? coords[0] : _nearbyLat,
      lng: coords.length > 1 ? coords[1] : _nearbyLng,
    );
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
      if (parts.isNotEmpty) {
        return parts.join(', ');
      }
    }
    return 'Unknown location';
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return 'Available';
    final DateTime? dateTime = DateTime.tryParse(value);
    if (dateTime == null) return 'Available';
    final String month = _monthNames[dateTime.month - 1];
    final String day = dateTime.day.toString().padLeft(2, '0');
    return '$month $day, ${dateTime.year}';
  }

  String _pickImageUrl(dynamic images) {
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is String) return first;
      if (first is Map && first['url'] != null) {
        return first['url'].toString();
      }
    }
    return '';
  }

  List<double> _readCoordinates(dynamic location) {
    if (location is Map) {
      final point = location['point'];
      if (point is Map && point['coordinates'] is List) {
        final List coords = point['coordinates'] as List;
        if (coords.length >= 2) {
          final double lngValue = _readDouble(coords[0]);
          final double latValue = _readDouble(coords[1]);
          return <double>[latValue, lngValue];
        }
      }
    }
    return <double>[];
  }

  List<String> _readStringList(dynamic value) {
    if (value is List) {
      return value
          .where((element) => element != null)
          .map((element) => element.toString())
          .where((element) => element.isNotEmpty)
          .toList();
    }
    return <String>[];
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

  double _calculateSearchResultsHeight() {
    if (_isSearching) return 88;
    if (_searchError != null) return 96;
    if (_searchResults.isEmpty) return 88;
    final int visibleResults = _searchResults.length < 4
        ? _searchResults.length
        : 4;
    return (visibleResults * 74 + 20).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final List<_PopularPlace> popularPlaces = _popularPlaces;
    final List<_RecommendedPlace> recommendedPlaces = _recommendedPlaces;
    final List<_PopularPlace> nearbyPreviewPlaces = popularPlaces
        .take(5)
        .toList(growable: false);
    final bool showSearchResults =
        _showSearchResults && _searchQuery.isNotEmpty;
    final double searchResultsHeight = _calculateSearchResultsHeight();

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Obx(() {
              final UserProfileDataModel profile =
                  ProfileController.instance().profile.value;
              final String name = profile.name.trim().isEmpty
                  ? 'Mack'
                  : profile.name.trim();
              return Row(
                children: <Widget>[
                  _ProfileAvatar(imageProvider: profile.avatarImageProvider),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Good Morning',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF3A4A5A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hello, $name',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1D2A36),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await context.push(NotificationRouteNames.notifications);
                      if (mounted) {
                        _loadUnreadCount();
                      }
                    },
                    child: _NotificationBell(unreadCount: _unreadCount),
                  ),
                ],
              );
            }),
            const SizedBox(height: 20),
            const Text(
              'Ready to fish today?',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D2A36),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: showSearchResults ? searchResultsHeight + 62 : 46,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  _SearchField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _searchSpots(),
                    onClear: _searchController.text.isEmpty
                        ? null
                        : _clearSearch,
                  ),
                  if (showSearchResults)
                    Positioned(
                      top: 54,
                      left: 0,
                      right: 0,
                      child: _HomeSearchResultsCard(
                        isLoading: _isSearching,
                        error: _searchError,
                        results: _searchResults,
                        onResultTap: _openSearchResult,
                      ),
                    ),
                ],
              ),
            ),
            Obx(() {
              final bool isLoading = _liveBookingController.isLoading.value;
              final String? liveError = _liveBookingController.error.value;
              final List<LiveBookingItem> liveEvents = _liveBookingController
                  .events
                  .toList(growable: false);
              final bool showLiveSection =
                  isLoading || liveError != null || liveEvents.isNotEmpty;

              if (!showLiveSection) {
                return const SizedBox(height: 18);
              }

              return Column(
                children: <Widget>[
                  const SizedBox(height: 22),
                  _SectionHeader(
                    title: 'Live',
                    actionLabel: 'See all',
                    onActionTap: () => _showMessage(context, 'Live'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 126,
                    child: isLoading
                        ? const _LiveEventCardSkeleton()
                        : liveError != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  liveError,
                                  style: const TextStyle(
                                    color: Color(0xFF6A7B8C),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                AppTextButton(
                                  onPressed:
                                      _liveBookingController.loadLiveBookings,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : PageView.builder(
                            controller: _liveController,
                            itemCount: liveEvents.length,
                            itemBuilder: (BuildContext context, int index) {
                              final LiveBookingItem liveEvent =
                                  liveEvents[index];
                              final String liveEventId =
                                  liveEvent.id?.trim() ?? '';
                              return AnimatedBuilder(
                                animation: _liveController,
                                child: _LiveEventCard(
                                  data: liveEvent,
                                  onStatusTap: () =>
                                      _handleLiveStatusTap(index),
                                  isActionLoading:
                                      liveEventId.isNotEmpty &&
                                      _liveBookingController.actionLoadingIds
                                          .contains(liveEventId),
                                ),
                                builder: (BuildContext context, Widget? child) {
                                  double scale = 1;
                                  double translate = 0;
                                  if (_liveController.hasClients) {
                                    final double page =
                                        _liveController.page ??
                                        _liveController.initialPage.toDouble();
                                    final double delta = (page - index).abs();
                                    scale = (1 - (delta * 0.05)).clamp(
                                      0.95,
                                      1.0,
                                    );
                                    translate = (delta * 6).clamp(0.0, 6.0);
                                  }
                                  return Transform.translate(
                                    offset: Offset(translate, 0),
                                    child: Transform.scale(
                                      scale: scale,
                                      alignment: Alignment.center,
                                      child: child,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 18),
                ],
              );
            }),
            _SectionHeader(
              title: 'Popular Nearby',
              actionLabel: 'See all',
              onActionTap: () => context.push(HomeRouteNames.popularNearby),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 476,
              child: _isLoadingNearby
                  ? ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: 2,
                      separatorBuilder: (_, _) => const SizedBox(width: 18),
                      itemBuilder: (_, _) => const _PopularCardSkeleton(),
                    )
                  : _nearbyError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            _nearbyError!,
                            style: const TextStyle(
                              color: Color(0xFF6A7B8C),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          AppTextButton(
                            onPressed: _loadNearbySpots,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : popularPlaces.isEmpty
                  ? const Center(
                      child: Text(
                        'No nearby spots found',
                        style: TextStyle(
                          color: Color(0xFF6A7B8C),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: nearbyPreviewPlaces.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 18),
                      itemBuilder: (BuildContext context, int index) {
                        final _PopularPlace place = nearbyPreviewPlaces[index];
                        return _PopularCard(
                          data: place,
                          onViewDetails: () {
                            final double lat = place.lat ?? _nearbyLat;
                            final double lng = place.lng ?? _nearbyLng;
                            final query = <String, String>{
                              'lat': lat.toString(),
                              'lng': lng.toString(),
                              'distanceKm': _nearbyDistanceKm.toString(),
                            };
                            if (place.id != null && place.id!.isNotEmpty) {
                              query['id'] = place.id!;
                            }
                            final detailsUri = Uri(
                              path: HomeRouteNames.details,
                              queryParameters: query,
                            );
                            context.push(detailsUri.toString());
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 18),
            _SectionHeader(
              title: 'Recommended',
              actionLabel: 'See all',
              onActionTap: () => context.push(HomeRouteNames.recommended),
            ),
            const SizedBox(height: 14),
            if (_isLoadingRecommended)
              const Column(
                children: <Widget>[
                  _RecommendedCardSkeleton(),
                  SizedBox(height: 14),
                  _RecommendedCardSkeleton(),
                ],
              )
            else if (_recommendedError != null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _recommendedError!,
                      style: const TextStyle(
                        color: Color(0xFF6A7B8C),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppTextButton(
                      onPressed: _loadRecommendedSpots,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            else if (recommendedPlaces.isEmpty)
              const Center(
                child: Text(
                  'No recommended spots found',
                  style: TextStyle(
                    color: Color(0xFF6A7B8C),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Column(
                children: recommendedPlaces
                    .take(5)
                    .map(
                      (_RecommendedPlace place) => _RecommendedCard(
                        data: place,
                        onTap: () {
                          final query = <String, String>{};
                          if (place.lat != null && place.lng != null) {
                            query['lat'] = place.lat.toString();
                            query['lng'] = place.lng.toString();
                            query['distanceKm'] = '15';
                          }
                          if (place.id != null && place.id!.isNotEmpty) {
                            query['id'] = place.id!;
                          }
                          final detailsUri = Uri(
                            path: HomeRouteNames.details,
                            queryParameters: query.isEmpty ? null : query,
                          );
                          context.push(detailsUri.toString());
                        },
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final ImageProvider imageProvider;

  const _ProfileAvatar({required this.imageProvider});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
        image: DecorationImage(
          image: imageProvider,
          fit: BoxFit.cover,
          onError: (_, _) {},
        ),
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  final int unreadCount;

  const _NotificationBell({this.unreadCount = 0});

  @override
  Widget build(BuildContext context) {
    final String badgeText = unreadCount > 99 ? '99+' : unreadCount.toString();
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Center(
            child: Icon(
              CupertinoIcons.bell_fill,
              color: Color(0xFF1787CF),
              size: 22,
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                height: 16,
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE23A3A),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback? onClear;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xD9FFFFFF), Color(0xA6FFFFFF)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0x99FFFFFF), width: 1.2),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 22,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(
                CupertinoIcons.search,
                color: Color(0xFF1E7CC8),
              ),
              hintText: 'Search',
              hintStyle: const TextStyle(
                color: Color(0xFF1E7CC8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              suffixIcon: onClear == null
                  ? null
                  : IconButton(
                      onPressed: onClear,
                      icon: const Icon(
                        CupertinoIcons.clear_circled_solid,
                        size: 18,
                        color: Color(0xFF8BA0B5),
                      ),
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
            style: const TextStyle(color: Color(0xFF1D2A36), fontSize: 14),
          ),
        ),
      ),
    );
  }
}

class _HomeSearchResultsCard extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final List<_HomeSearchResult> results;
  final ValueChanged<_HomeSearchResult> onResultTap;

  const _HomeSearchResultsCard({
    required this.isLoading,
    required this.error,
    required this.results,
    required this.onResultTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 316),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xD9FFFFFF), Color(0xB3EEF6FF)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xAAFFFFFF), width: 1.2),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x220F172A),
                  blurRadius: 26,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: isLoading
                  ? const SizedBox(
                      height: 88,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : error != null
                  ? SizedBox(
                      height: 96,
                      child: Center(
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Color(0xFF6A7B8C),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : results.isEmpty
                  ? const SizedBox(
                      height: 88,
                      child: Center(
                        child: Text(
                          'No matching spots found',
                          style: TextStyle(
                            color: Color(0xFF6A7B8C),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shrinkWrap: true,
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final _HomeSearchResult result = results[index];
                        return _HomeSearchResultTile(
                          result: result,
                          onTap: () => onResultTap(result),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSearchResultTile extends StatelessWidget {
  final _HomeSearchResult result;
  final VoidCallback onTap;

  const _HomeSearchResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF4FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                CupertinoIcons.location_solid,
                color: Color(0xFF1787CF),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D2A36),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    result.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6A7B8C),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '\$${result.price}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1787CF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onActionTap;

  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1D2A36),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onActionTap,
          child: Text(
            actionLabel,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A7B8C),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveEventCard extends StatelessWidget {
  final LiveBookingItem data;
  final VoidCallback onStatusTap;
  final bool isActionLoading;

  const _LiveEventCard({
    required this.data,
    required this.onStatusTap,
    required this.isActionLoading,
  });

  @override
  Widget build(BuildContext context) {
    final String statusLabel = data.statusLabel;
    final Color statusColor = !data.canUpdateAttendance
        ? const Color(0xFF94A3B8)
        : data.isArrived
        ? const Color(0xFF111827)
        : const Color(0xFF1787CF);
    return Container(
      width: double.infinity,
      height: 118,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1787CF), width: 1.4),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: Image.network(
              data.imageUrl,
              width: 125,
              height: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 98,
                height: double.infinity,
                color: const Color(0xFFE2E8F1),
                child: const Icon(Icons.photo, size: 28),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D2A36),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _LiveMetaRow(icon: CupertinoIcons.time, text: data.time),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _LiveMetaRow(
                          icon: CupertinoIcons.location_solid,
                          text: data.location,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _LiveMetaRow(
                          icon: CupertinoIcons.calendar,
                          text: data.date,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 12,
                        backgroundImage: NetworkImage(data.hostAvatarUrl),
                        backgroundColor: const Color(0xFFE2E8F1),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              data.hostName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D2A36),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: <Widget>[
                                const Icon(
                                  CupertinoIcons.star_fill,
                                  size: 11,
                                  color: Color(0xFFF2B01E),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '${data.rating} (${data.reviews} Reviews)',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6A7B8C),
                                    ),
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
                          onPressed:
                              isActionLoading || !data.canUpdateAttendance
                              ? null
                              : onStatusTap,
                          loadingColor: Colors.white,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: statusColor,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            statusLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
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
        ],
      ),
    );
  }
}

class _LiveEventCardSkeleton extends StatelessWidget {
  const _LiveEventCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 118,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0ECF8), width: 1.2),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: const <Widget>[
          AppShimmerBox(
            width: 125,
            height: double.infinity,
            borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppShimmerBox(width: 120, height: 14),
                  SizedBox(height: 8),
                  AppShimmerBox(width: 100, height: 10),
                  SizedBox(height: 6),
                  AppShimmerBox(width: 150, height: 10),
                  Spacer(),
                  Row(
                    children: <Widget>[
                      AppShimmerBox(
                        width: 24,
                        height: 24,
                        shape: BoxShape.circle,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            AppShimmerBox(width: 90, height: 10),
                            SizedBox(height: 6),
                            AppShimmerBox(width: 110, height: 10),
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      AppShimmerBox(width: 72, height: 28),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMetaRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _LiveMetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 11, color: const Color(0xFF6A7B8C)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF6A7B8C),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _PopularMetaItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;
  final Color textColor;
  final double maxWidth;
  final FontWeight fontWeight;

  const _PopularMetaItem({
    required this.icon,
    required this.text,
    required this.maxWidth,
    this.iconColor = const Color(0xFF3A4A5A),
    this.textColor = const Color(0xFF3A4A5A),
    this.fontWeight = FontWeight.w500,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: textColor,
                fontWeight: fontWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopularCard extends StatelessWidget {
  final _PopularPlace data;
  final VoidCallback onViewDetails;

  const _PopularCard({required this.data, required this.onViewDetails});

  @override
  Widget build(BuildContext context) {
    final List<String> visibleTags = data.tags.take(3).toList(growable: false);
    final int hiddenTagCount = data.tags.length - visibleTags.length;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Image.network(
              data.imageUrl,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 180,
                color: const Color(0xFFE2E8F1),
                child: const Icon(Icons.photo, size: 40),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        data.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1D2A36),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF4FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: RichText(
                        text: TextSpan(
                          children: <TextSpan>[
                            TextSpan(
                              text: '\$${data.pricePerDay}',
                              style: const TextStyle(
                                color: Color(0xFF1787CF),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(
                              text: '/day',
                              style: TextStyle(
                                color: Color(0xFF1D2A36),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    _PopularMetaItem(
                      icon: CupertinoIcons.location_solid,
                      text: data.location,
                      maxWidth: 150,
                    ),
                    _PopularMetaItem(
                      icon: CupertinoIcons.calendar,
                      text: data.date,
                      maxWidth: 110,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            CupertinoIcons.star_fill,
                            size: 16,
                            color: Color(0xFFF2B01E),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${data.rating}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1D2A36),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '(${data.reviews} Reviews)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6A7B8C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _PopularMetaItem(
                      icon: CupertinoIcons.time,
                      text: data.timeRange,
                      maxWidth: 100,
                      iconColor: const Color(0xFF1D2A36),
                      textColor: const Color(0xFF1D2A36),
                      fontWeight: FontWeight.w600,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ...visibleTags.map(
                      (String tag) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F3F7),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF39424E),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (hiddenTagCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6EEF8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '+$hiddenTagCount more',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1787CF),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    _AvatarStack(avatars: data.attendees),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            data.attendeesLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF1D2A36),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.attendeesSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6A7B8C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: AppElevatedButton(
                    onPressed: onViewDetails,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1787CF),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
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
}

class _PopularCardSkeleton extends StatelessWidget {
  const _PopularCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppShimmerBox(
            height: 180,
            width: double.infinity,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: AppShimmerBox(height: 18)),
                    SizedBox(width: 12),
                    AppShimmerBox(width: 88, height: 38),
                  ],
                ),
                SizedBox(height: 10),
                AppShimmerBox(width: 170, height: 12),
                SizedBox(height: 8),
                AppShimmerBox(width: 140, height: 12),
                SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    AppShimmerBox(width: 68, height: 28),
                    AppShimmerBox(width: 78, height: 28),
                    AppShimmerBox(width: 60, height: 28),
                  ],
                ),
                SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    AppShimmerBox(width: 110, height: 32),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppShimmerBox(width: 90, height: 12),
                          SizedBox(height: 6),
                          AppShimmerBox(width: 130, height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                AppShimmerBox(height: 34, width: double.infinity),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  final List<String> avatars;

  const _AvatarStack({required this.avatars});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      height: 36,
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < avatars.length; index++)
            Positioned(
              left: index * 20,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  image: DecorationImage(
                    image: NetworkImage(avatars[index]),
                    fit: BoxFit.cover,
                    onError: (_, _) {},
                  ),
                ),
              ),
            ),
          Positioned(
            left: avatars.length * 20,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFDCEAF8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Text(
                '4+',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1D2A36),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedCard extends StatelessWidget {
  final _RecommendedPlace data;
  final VoidCallback onTap;

  const _RecommendedCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                data.imageUrl,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: const Color(0xFFE2E8F1),
                  child: const Icon(Icons.photo, size: 30),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    data.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D2A36),
                    ),
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          return Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const Icon(
                                      CupertinoIcons.location_solid,
                                      size: 14,
                                      color: Color(0xFF3A4A5A),
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        data.location,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF3A4A5A),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const Icon(
                                    CupertinoIcons.calendar,
                                    size: 14,
                                    color: Color(0xFF3A4A5A),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    data.date,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF3A4A5A),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            CupertinoIcons.star_fill,
                            size: 14,
                            color: Color(0xFFF2B01E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${data.rating}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1D2A36),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${data.reviews} Reviews)',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6A7B8C),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(
                            CupertinoIcons.time,
                            size: 14,
                            color: Color(0xFF1D2A36),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            data.timeRange,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1D2A36),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedCardSkeleton extends StatelessWidget {
  const _RecommendedCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        children: <Widget>[
          AppShimmerBox(width: 64, height: 64),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppShimmerBox(width: 150, height: 14),
                SizedBox(height: 8),
                AppShimmerBox(width: 180, height: 11),
                SizedBox(height: 8),
                AppShimmerBox(width: 140, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSearchResult {
  final String id;
  final String title;
  final String location;
  final int price;
  final double lat;
  final double lng;

  const _HomeSearchResult({
    required this.id,
    required this.title,
    required this.location,
    required this.price,
    required this.lat,
    required this.lng,
  });
}

class _PopularPlace {
  final String? id;
  final String title;
  final String location;
  final String date;
  final double rating;
  final int reviews;
  final String timeRange;
  final int pricePerDay;
  final String imageUrl;
  final List<String> tags;
  final List<String> attendees;
  final String attendeesLabel;
  final String attendeesSubtitle;
  final double? lat;
  final double? lng;

  const _PopularPlace({
    this.id,
    required this.title,
    required this.location,
    required this.date,
    required this.rating,
    required this.reviews,
    required this.timeRange,
    required this.pricePerDay,
    required this.imageUrl,
    required this.tags,
    required this.attendees,
    required this.attendeesLabel,
    required this.attendeesSubtitle,
    this.lat,
    this.lng,
  });
}

class _RecommendedPlace {
  final String? id;
  final String title;
  final String location;
  final String date;
  final double rating;
  final int reviews;
  final String timeRange;
  final String imageUrl;
  final double? lat;
  final double? lng;

  const _RecommendedPlace({
    this.id,
    required this.title,
    required this.location,
    required this.date,
    required this.rating,
    required this.reviews,
    required this.timeRange,
    required this.imageUrl,
    this.lat,
    this.lng,
  });
}
