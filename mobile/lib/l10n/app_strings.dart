/// Centralized user-facing strings (English).
///
/// All screen copy lives here — never scatter literal UI text through
/// widgets. English is the initial locale. To add Nepali (ne) later,
/// introduce a per-locale instance (e.g. `class NeStrings implements
/// AppStrings`) and switch on `Localizations.localeOf(context)`; the
/// screens only need a lookup helper change, no screen rewrites.
abstract final class AppStrings {
  static const String appName = 'Guides Nepal';
  static const String tagline = 'Discover Nepal Through Local Eyes';
  static const String heroHeadline = 'Find your Nepal.';
  static const String heroSubline =
      'Discover remarkable places and unforgettable experiences with the '
      'people who know them best.';

  // Navigation
  static const String navHome = 'Home';
  static const String navExplore = 'Explore';
  static const String navTrips = 'Trips';
  static const String navInbox = 'Inbox';
  static const String navSaved = 'Saved';
  static const String navProfile = 'Profile';

  // Common actions
  static const String exploreExperiences = 'Explore experiences';
  static const String seeAll = 'See all';
  static const String retry = 'Try again';
  static const String cancel = 'Cancel';
  static const String save = 'Save';
  static const String done = 'Done';
  static const String close = 'Close';
  static const String share = 'Share';
  static const String back = 'Back';
  static const String continueLabel = 'Continue';

  // States
  static const String loading = 'Loading…';
  static const String emptyTitle = 'Nothing here yet';
  static const String errorTitle = 'Something went wrong';
  static const String offlineTitle = 'No connection';
  static const String offlineBody =
      'We could not reach Guides Nepal. Check your connection and try again.';
  static const String sessionExpiredTitle = 'Session expired';
  static const String sessionExpiredBody =
      'Please sign in again to continue.';

  // Auth
  static const String signIn = 'Sign in';
  static const String signUp = 'Create account';
  static const String signOut = 'Sign out';
  static const String emailLabel = 'Email';
  static const String passwordLabel = 'Password';
  static const String forgotPassword = 'Forgot password?';

  // Booking
  static const String bookNow = 'Book now';
  static const String checkAvailability = 'Check availability';
  static const String from = 'from';

  // AI
  static const String mailaDai = 'Maila Dai';
  static const String mailaDaiIntro =
      'Namaste! I\'m Maila Dai, your local travel companion. Ask me about '
      'destinations, food, culture, or adventure in Nepal.';

  // Tabs
  static const String homeSubline = 'Where will you explore today?';
  static const String localUpdates = 'Local updates';
  static const String exploreSubline =
      'Hand-picked experiences with local guides';
  static const String tripsSubline = 'Every experience you have booked';
  static const String inboxSubline = 'Your conversations with guides';
  static const String inboxComingTitle = 'Direct messages are on the way';
  static const String inboxComingBody =
      'Once guide messaging launches, your conversations will appear here. '
      'Until then Maila Dai can answer travel questions any time.';
  static const String planWithMailaDai = 'Plan with Maila Dai';
  static const String planWithMailaDaiBody =
      'Routes, food, culture and timing — ask your local travel assistant.';

  // Sections
  static const String sectionYourActivity = 'Your activity';
  static const String sectionPlanSupport = 'Plan & support';
  static const String sectionGuideTools = 'Guide tools';
  static const String sectionAccount = 'Account';
  static const String groupUpcoming = 'Upcoming';
  static const String groupPast = 'Past trips';
  static const String clearFilters = 'Clear all';

  // Explore
  static const String exploreTitle = 'Explore';
  static const String searchHint = 'Search experiences, places, guides';
  static const String sortBy = 'Sort by';
  static const String priceRange = 'Price range';
  static const String allCities = 'All cities';
  static const String noExperiencesTitle = 'No experiences found';
  static const String noExperiencesBody =
      'Try a different city, category, price, or search term.';
}
