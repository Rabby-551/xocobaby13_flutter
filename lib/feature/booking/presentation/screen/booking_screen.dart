import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:xocobaby13/feature/home/presentation/routes/home_routes.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  int _selectedTabIndex = 0;

  final List<String> _tabs = <String>['Ongoing', 'Completed', 'Upcoming'];

  final List<_BookingItem> _bookings = <_BookingItem>[
    const _BookingItem(
      title: 'Crystal Lake Sanctuary',
      time: '7:00 AM - 5:00 PM',
      location: 'Montana, USA',
      date: 'Feb 05, 2026',
      price: 120,
      ownerName: 'Spot Owner',
      rating: 4.5,
      reviews: 18,
      imageUrl:
          'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1000&q=80',
      ownerAvatarUrl:
          'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=200&q=80',
    ),
    const _BookingItem(
      title: 'Crystal Lake Sanctuary',
      time: '7:00 AM - 5:00 PM',
      location: 'Montana, USA',
      date: 'Feb 05, 2026',
      price: 120,
      ownerName: 'Spot Owner',
      rating: 4.5,
      reviews: 18,
      imageUrl:
          'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1000&q=80',
      ownerAvatarUrl:
          'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=200&q=80',
    ),
    const _BookingItem(
      title: 'Crystal Lake Sanctuary',
      time: '7:00 AM - 5:00 PM',
      location: 'Montana, USA',
      date: 'Feb 05, 2026',
      price: 120,
      ownerName: 'Spot Owner',
      rating: 4.5,
      reviews: 18,
      imageUrl:
          'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=1000&q=80',
      ownerAvatarUrl:
          'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=200&q=80',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: List<Widget>.generate(
                  _tabs.length,
                  (int index) => Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: _BookingTab(
                      label: _tabs[index],
                      isSelected: _selectedTabIndex == index,
                      onTap: () => setState(() => _selectedTabIndex = index),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Column(
              children: _bookings
                  .map(
                    (_BookingItem item) => _BookingCard(
                      item: item,
                      onViewDetails: () => context.push(HomeRouteNames.details),
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

class _BookingTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BookingTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 116),
        child: Column(
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF1D2A36),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 110,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1787CF) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x331787CF),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final _BookingItem item;
  final VoidCallback onViewDetails;

  const _BookingCard({required this.item, required this.onViewDetails});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 140,
                height: 110,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: NetworkImage(item.imageUrl),
                    fit: BoxFit.cover,
                    onError: (_, __) {},
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1D2A36),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        const Icon(
                          CupertinoIcons.time,
                          size: 16,
                          color: Color(0xFF1D2A36),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.time,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1D2A36),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        const Icon(
                          CupertinoIcons.location,
                          size: 16,
                          color: Color(0xFF1D2A36),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.location,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1D2A36),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          CupertinoIcons.calendar,
                          size: 16,
                          color: Color(0xFF1D2A36),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.date,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1D2A36),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        _Avatar(imageUrl: item.ownerAvatarUrl),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.ownerName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1D2A36),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: <Widget>[
                                  const Icon(
                                    CupertinoIcons.star_fill,
                                    size: 14,
                                    color: Color(0xFFF4B400),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${item.rating}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1D2A36),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '(${item.reviews} Reviews)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF1D2A36),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE9F4FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: RichText(
                            text: TextSpan(
                              text: '\$${item.price}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1787CF),
                              ),
                              children: const <TextSpan>[
                                TextSpan(
                                  text: '/day',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF1D2A36),
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
              ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onViewDetails,
            child: Container(
              height: 46,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1787CF), width: 1.4),
                color: Colors.white,
              ),
              child: const Text(
                'View Details',
                style: TextStyle(
                  color: Color(0xFF1787CF),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String imageUrl;

  const _Avatar({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        image: DecorationImage(
          image: NetworkImage(imageUrl),
          fit: BoxFit.cover,
          onError: (_, __) {},
        ),
      ),
    );
  }
}

class _BookingItem {
  final String title;
  final String time;
  final String location;
  final String date;
  final int price;
  final String ownerName;
  final double rating;
  final int reviews;
  final String imageUrl;
  final String ownerAvatarUrl;

  const _BookingItem({
    required this.title,
    required this.time,
    required this.location,
    required this.date,
    required this.price,
    required this.ownerName,
    required this.rating,
    required this.reviews,
    required this.imageUrl,
    required this.ownerAvatarUrl,
  });
}
