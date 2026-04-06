import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../services/haptic_service.dart';

// ─── TermsScreen ──────────────────────────────────────────────────────────────
//
// Combined Terms of Service and Privacy Policy screen.
// Accessible from the auth/onboarding screen via a small footer link.
// Last updated: April 2026.

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Legal'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          tooltip: 'Back',
          onPressed: () {
            HapticService.selection();
            context.pop();
          },
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          indicatorWeight: 2,
          labelStyle: AppTextStyles.labelLarge.copyWith(fontSize: 13),
          unselectedLabelStyle:
              AppTextStyles.bodyMedium.copyWith(fontSize: 13),
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Terms of Service'),
            Tab(text: 'Privacy Policy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _LegalSection(content: _kTermsContent),
          _LegalSection(content: _kPrivacyContent),
        ],
      ),
    );
  }
}

// ─── Scrollable section ───────────────────────────────────────────────────────

class _LegalSection extends StatelessWidget {
  final List<_LegalBlock> content;
  const _LegalSection({required this.content});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        20, 20, 20,
        MediaQuery.of(context).padding.bottom + 32,
      ),
      itemCount: content.length,
      itemBuilder: (_, i) {
        final block = content[i];
        return switch (block.type) {
          _BlockType.heading => Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 6),
              child: Text(
                block.text,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.accent,
                  fontSize: 15,
                ),
              ),
            ),
          _BlockType.subheading => Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text(
                block.text,
                style: AppTextStyles.labelLarge.copyWith(fontSize: 13),
              ),
            ),
          _BlockType.body => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                block.text,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          _BlockType.bullet => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      block.text,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _BlockType.updated => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                block.text,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
        };
      },
    );
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

enum _BlockType { heading, subheading, body, bullet, updated }

class _LegalBlock {
  final _BlockType type;
  final String text;
  const _LegalBlock(this.type, this.text);
}

// ─── Terms of Service content ─────────────────────────────────────────────────

const _kTermsContent = <_LegalBlock>[
  _LegalBlock(_BlockType.updated, 'Last updated: April 6, 2026'),

  _LegalBlock(_BlockType.body,
      'Please read these Terms of Service ("Terms") carefully before using the Tavera mobile application ("App", "Service") operated by Tavera ("we", "us", "our"). By accessing or using the App you agree to be bound by these Terms.'),

  _LegalBlock(_BlockType.heading, '1. Acceptance of Terms'),
  _LegalBlock(_BlockType.body,
      'By creating an account or using the App in any way, you confirm that you are at least 13 years of age (or the minimum age of digital consent in your country) and that you accept these Terms in full. If you do not agree, you must not use the Service.'),

  _LegalBlock(_BlockType.heading, '2. Description of Service'),
  _LegalBlock(_BlockType.body,
      'Tavera is an AI-powered calorie and nutrition tracking application. The App uses computer vision and third-party AI models to estimate the nutritional content of food from photographs or barcode scans. Features include:'),
  _LegalBlock(_BlockType.bullet, 'Camera-based meal logging with AI macro estimation'),
  _LegalBlock(_BlockType.bullet, 'Barcode scanning via Open Food Facts database'),
  _LegalBlock(_BlockType.bullet, 'Weekly AI coaching insights (Premium)'),
  _LegalBlock(_BlockType.bullet, 'Calorie banking, GLP-1 mode, and intermittent fasting timer'),
  _LegalBlock(_BlockType.bullet, 'Meal planning and social challenges (Premium)'),

  _LegalBlock(_BlockType.heading, '3. Medical Disclaimer'),
  _LegalBlock(_BlockType.body,
      'THE APP IS NOT A MEDICAL DEVICE AND IS NOT INTENDED TO DIAGNOSE, TREAT, CURE, OR PREVENT ANY DISEASE OR MEDICAL CONDITION. All calorie and nutrition estimates are approximations generated by AI models and should not be relied upon as precise measurements. Always consult a qualified healthcare professional before making significant dietary changes, especially if you have a medical condition, are pregnant, or are taking medications including GLP-1 agonists.'),

  _LegalBlock(_BlockType.heading, '4. User Accounts'),
  _LegalBlock(_BlockType.body,
      'You are responsible for maintaining the confidentiality of your account credentials and for all activity that occurs under your account. You must notify us immediately of any unauthorised use. We reserve the right to terminate accounts that violate these Terms.'),

  _LegalBlock(_BlockType.heading, '5. Subscriptions and Billing'),
  _LegalBlock(_BlockType.subheading, '5.1 Free Tier'),
  _LegalBlock(_BlockType.body,
      'The Free tier allows up to 3 meal logs per day and provides calorie-only tracking with limited history.'),
  _LegalBlock(_BlockType.subheading, '5.2 Premium Subscription'),
  _LegalBlock(_BlockType.body,
      'Premium is available as a monthly or annual auto-renewing subscription managed through the Apple App Store or Google Play Store. Prices are displayed at the time of purchase. Payment is charged to your store account upon confirmation of purchase. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period.'),
  _LegalBlock(_BlockType.subheading, '5.3 Refunds'),
  _LegalBlock(_BlockType.body,
      'Refund requests are handled by Apple or Google in accordance with their respective policies. We do not process refunds directly.'),

  _LegalBlock(_BlockType.heading, '6. Acceptable Use'),
  _LegalBlock(_BlockType.body, 'You agree not to:'),
  _LegalBlock(_BlockType.bullet, 'Use the App for any unlawful purpose'),
  _LegalBlock(_BlockType.bullet, 'Attempt to reverse-engineer, decompile, or extract source code from the App'),
  _LegalBlock(_BlockType.bullet, 'Upload content that is harmful, offensive, or infringes on third-party rights'),
  _LegalBlock(_BlockType.bullet, 'Interfere with the App\'s infrastructure or other users\' access'),
  _LegalBlock(_BlockType.bullet, 'Use automated tools to scrape or extract data from the Service'),

  _LegalBlock(_BlockType.heading, '7. Intellectual Property'),
  _LegalBlock(_BlockType.body,
      'The App, its design, code, trademarks, and content are owned by or licensed to Tavera. Nothing in these Terms grants you any rights in our intellectual property other than the limited licence to use the App as described herein.'),

  _LegalBlock(_BlockType.heading, '8. Third-Party Services'),
  _LegalBlock(_BlockType.body,
      'The App integrates third-party services including Supabase (database), Google Gemini (AI), Open Food Facts (product database), RevenueCat (subscriptions), PostHog (analytics), and Firebase (notifications). Your use of these integrations is subject to their respective terms and privacy policies.'),

  _LegalBlock(_BlockType.heading, '9. Disclaimer of Warranties'),
  _LegalBlock(_BlockType.body,
      'THE SERVICE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND. WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR FREE OF HARMFUL COMPONENTS.'),

  _LegalBlock(_BlockType.heading, '10. Limitation of Liability'),
  _LegalBlock(_BlockType.body,
      'TO THE FULLEST EXTENT PERMITTED BY LAW, TAVERA SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES ARISING FROM YOUR USE OF THE SERVICE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. OUR TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT YOU PAID US IN THE 12 MONTHS PRECEDING THE CLAIM.'),

  _LegalBlock(_BlockType.heading, '11. Governing Law'),
  _LegalBlock(_BlockType.body,
      'These Terms are governed by and construed in accordance with applicable law. Any disputes shall be resolved through binding arbitration, except where prohibited by law.'),

  _LegalBlock(_BlockType.heading, '12. Changes to Terms'),
  _LegalBlock(_BlockType.body,
      'We may update these Terms periodically. Material changes will be notified via in-app notification or email. Continued use of the App after changes constitutes acceptance of the updated Terms.'),

  _LegalBlock(_BlockType.heading, '13. Contact'),
  _LegalBlock(_BlockType.body,
      'For questions about these Terms, contact us at: legal@tavera.app'),
];

// ─── Privacy Policy content ───────────────────────────────────────────────────

const _kPrivacyContent = <_LegalBlock>[
  _LegalBlock(_BlockType.updated, 'Last updated: April 6, 2026'),

  _LegalBlock(_BlockType.body,
      'This Privacy Policy explains how Tavera ("we", "us", "our") collects, uses, and protects your personal information when you use the Tavera app. We are committed to protecting your privacy and handling your data with transparency.'),

  _LegalBlock(_BlockType.heading, '1. Information We Collect'),
  _LegalBlock(_BlockType.subheading, '1.1 Account Information'),
  _LegalBlock(_BlockType.bullet, 'Email address and display name'),
  _LegalBlock(_BlockType.bullet, 'Password (stored as a secure hash — never in plain text)'),
  _LegalBlock(_BlockType.bullet, 'Profile photo URL (if provided)'),

  _LegalBlock(_BlockType.subheading, '1.2 Health & Nutrition Data'),
  _LegalBlock(_BlockType.bullet, 'Meal logs including food names, calories, and macronutrients'),
  _LegalBlock(_BlockType.bullet, 'Meal photos (uploaded temporarily for AI analysis, not stored long-term)'),
  _LegalBlock(_BlockType.bullet, 'Body stats you voluntarily provide: weight, height, age, biological sex'),
  _LegalBlock(_BlockType.bullet, 'Calorie goal and dietary preferences'),
  _LegalBlock(_BlockType.bullet, 'Fasting sessions, mood and energy ratings'),
  _LegalBlock(_BlockType.bullet, 'GLP-1 mode flag (if enabled)'),
  _LegalBlock(_BlockType.bullet, 'Water intake logs'),

  _LegalBlock(_BlockType.subheading, '1.3 Usage Data'),
  _LegalBlock(_BlockType.bullet, 'App interactions and feature usage (via PostHog analytics)'),
  _LegalBlock(_BlockType.bullet, 'Crash reports and performance diagnostics'),
  _LegalBlock(_BlockType.bullet, 'Device type, OS version, and app version'),

  _LegalBlock(_BlockType.subheading, '1.4 Device Permissions'),
  _LegalBlock(_BlockType.body,
      'We request the following permissions and explain why:'),
  _LegalBlock(_BlockType.bullet, 'Camera — to photograph meals for AI analysis and barcode scanning'),
  _LegalBlock(_BlockType.bullet, 'Photo library — to select existing photos for logging'),
  _LegalBlock(_BlockType.bullet, 'Notifications — to send meal reminders (optional, you can disable at any time)'),

  _LegalBlock(_BlockType.heading, '2. How We Use Your Information'),
  _LegalBlock(_BlockType.body, 'We use your data to:'),
  _LegalBlock(_BlockType.bullet, 'Provide and personalise the App experience'),
  _LegalBlock(_BlockType.bullet, 'Generate AI coaching insights based on your nutrition patterns'),
  _LegalBlock(_BlockType.bullet, 'Calculate calorie goals and macro recommendations'),
  _LegalBlock(_BlockType.bullet, 'Send meal reminders and challenge notifications'),
  _LegalBlock(_BlockType.bullet, 'Improve the App and fix bugs'),
  _LegalBlock(_BlockType.bullet, 'Comply with legal obligations'),
  _LegalBlock(_BlockType.body,
      'We do NOT sell your personal information to third parties. We do NOT use your health data for advertising purposes.'),

  _LegalBlock(_BlockType.heading, '3. Data Storage and Security'),
  _LegalBlock(_BlockType.body,
      'Your data is stored in Supabase (PostgreSQL) with row-level security policies ensuring you can only access your own records. Data is encrypted in transit (TLS 1.3) and at rest. Meal photos sent for AI analysis are transmitted over HTTPS and are not stored by us after analysis is complete.'),

  _LegalBlock(_BlockType.heading, '4. Data Sharing'),
  _LegalBlock(_BlockType.body, 'We share data only with:'),
  _LegalBlock(_BlockType.bullet,
      'Google Gemini — meal photos and text are sent for AI analysis. Google\'s data processing terms apply.'),
  _LegalBlock(_BlockType.bullet,
      'Supabase — database and authentication provider. EU-hosted where possible.'),
  _LegalBlock(_BlockType.bullet,
      'RevenueCat — subscription management. Purchase history is shared to verify premium status.'),
  _LegalBlock(_BlockType.bullet,
      'PostHog — anonymised usage analytics. No personally identifiable health data is shared.'),
  _LegalBlock(_BlockType.bullet,
      'Firebase — push notification token only; message content is not logged.'),
  _LegalBlock(_BlockType.bullet,
      'Law enforcement — only when required by valid legal process.'),

  _LegalBlock(_BlockType.heading, '5. Your Rights'),
  _LegalBlock(_BlockType.body,
      'Depending on your jurisdiction, you may have the right to:'),
  _LegalBlock(_BlockType.bullet, 'Access a copy of all personal data we hold about you'),
  _LegalBlock(_BlockType.bullet, 'Correct inaccurate data'),
  _LegalBlock(_BlockType.bullet, 'Delete your account and all associated data'),
  _LegalBlock(_BlockType.bullet, 'Export your data in a machine-readable format'),
  _LegalBlock(_BlockType.bullet, 'Opt out of analytics tracking'),
  _LegalBlock(_BlockType.body,
      'To exercise these rights, delete your account from Profile → Account → Delete Account, or contact privacy@tavera.app.'),

  _LegalBlock(_BlockType.heading, '6. Data Retention'),
  _LegalBlock(_BlockType.body,
      'Your data is retained as long as your account is active. Upon account deletion, all personally identifiable data is permanently deleted within 30 days. Anonymised, aggregated analytics data may be retained longer.'),

  _LegalBlock(_BlockType.heading, '7. Children\'s Privacy'),
  _LegalBlock(_BlockType.body,
      'The App is not intended for users under 13. We do not knowingly collect personal information from children under 13. If we become aware that a child under 13 has provided personal information, we will delete it promptly.'),

  _LegalBlock(_BlockType.heading, '8. Cookies and Tracking'),
  _LegalBlock(_BlockType.body,
      'The App does not use browser cookies. PostHog analytics uses a persistent anonymous device identifier that does not contain personally identifiable information. You can opt out of analytics at any time in Profile → Settings.'),

  _LegalBlock(_BlockType.heading, '9. International Transfers'),
  _LegalBlock(_BlockType.body,
      'Your data may be processed in countries outside your own, including the United States. We ensure such transfers are covered by appropriate safeguards (e.g., Standard Contractual Clauses) where required by law.'),

  _LegalBlock(_BlockType.heading, '10. Changes to This Policy'),
  _LegalBlock(_BlockType.body,
      'We may update this Privacy Policy. Significant changes will be communicated via in-app notice or email. The "Last updated" date at the top always reflects the most recent revision.'),

  _LegalBlock(_BlockType.heading, '11. Contact'),
  _LegalBlock(_BlockType.body,
      'For privacy-related questions or requests, contact: privacy@tavera.app'),
];
