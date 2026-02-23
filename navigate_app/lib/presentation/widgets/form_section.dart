import 'package:flutter/material.dart';

/// כותרת סעיף ממוספרת עבור דף משתנים
class FormSection extends StatelessWidget {
  final int sectionNumber;
  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const FormSection({
    super.key,
    required this.sectionNumber,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Text(
              '$sectionNumber. $title',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.blue.shade900,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: child,
          ),
        ],
      ),
    );
  }
}
