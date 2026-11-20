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
  static const String emailRequired = 'Email is required';
  static const String emailInvalid = 'Enter a valid email';
  static const String passwordRequired = 'Password is required';
  static const String passwordTooShort = 'Use at least 8 characters';
  static const String passwordMismatch = 'Passwords do not match';
  static const String genericError = 'Something went wrong. Please try again.';

  // Password recovery (`POST /auth/forgot-password`)
  static const String forgotPasswordTitle = 'Reset your password';
  static const String forgotPasswordBody =
      'Enter the email on your account and we will send a reset link if one '
      'is registered.';
  static const String sendResetLink = 'Send reset link';
  static const String resetLinkSentTitle = 'Check your inbox';
  static const String resetDeliveryNote =
      'Email delivery depends on the mail service configured for this '
      'deployment. If nothing arrives, contact support and we will help you '
      'back in.';
  static const String backToSignIn = 'Back to sign in';
  static const String contactSupport = 'Contact support';

  // Change password (`POST /auth/change-password`)
  static const String changePassword = 'Change password';
  static const String changePasswordSubtitle =
      'Update the password you sign in with';
  static const String currentPasswordLabel = 'Current password';
  static const String newPasswordLabel = 'New password';
  static const String confirmPasswordLabel = 'Confirm new password';
  static const String currentPasswordRequired =
      'Enter your current password';
  static const String passwordUpdated = 'Password updated';

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
  static const String inboxEmptyTitle = 'No conversations yet';
  static const String inboxEmptyBody =
      'Book an experience, then message your guide from Trips — your '
      'conversations appear here.';
  static const String messagesSection = 'Messages';
  static const String messageGuide = 'Message guide';
  static const String messageHint = 'Write a message…';
  static const String conversationNoMessages = 'No messages yet';
  static const String threadEmptyTitle =
      'Say namaste — send the first message';
  static const String planWithMailaDai = 'Plan with Maila Dai';
  static const String planWithMailaDaiBody =
      'Routes, food, culture and timing — ask your local travel assistant.';

  // Profile editing
  static const String editProfile = 'Edit profile';
  static const String editProfileSubtitle =
      'Your name, photo and contact details';
  static const String firstNameLabel = 'First name';
  static const String lastNameLabel = 'Last name';
  static const String phoneLabel = 'Phone';
  static const String bioLabel = 'About you';
  static const String bioHelper = 'Optional — a line guides can read before you meet.';
  static const String changePhoto = 'Change photo';
  static const String removePhoto = 'Remove photo';
  static const String profileSaved = 'Profile updated';
  static const String nameRequired =
      'Add a first or last name so guides know who they are meeting.';
  static const String phoneInvalid = 'Use digits, spaces, brackets, + or - only.';
  static const String fieldTooLong = 'This is too long.';
  static const String photoTooLarge = 'Choose a photo smaller than 5 MB.';

  // Host workspace (`/host/*` — host role only)
  static const String hostDashboard = 'Host dashboard';
  static const String hostToolsSubtitle =
      'Your experiences, tours and booking requests';
  static const String hostWorkspaceOnlyTitle = 'Host workspace';
  static const String hostWorkspaceOnlyBody =
      'This workspace is available to host accounts.';
  static const String hostTabExperiences = 'Experiences';
  static const String hostTabTours = 'Tours';
  static const String hostTabBookings = 'Bookings';
  static const String hostExperiencesTitle = 'Your experiences';
  static const String hostToursTitle = 'Your tours';
  static const String hostBookingsTitle = 'Booking requests';
  static const String hostNewExperience = 'New experience';
  static const String hostNewTour = 'New tour';
  static const String hostCreateExperience = 'Create experience';
  static const String hostEditExperience = 'Edit experience';
  static const String hostCreateTour = 'Create tour';
  static const String hostEditTour = 'Edit tour';
  static const String hostNoExperiencesTitle = 'No experiences yet';
  static const String hostNoExperiencesBody =
      'Add an experience so travellers can find it and book it.';
  static const String hostNoToursTitle = 'No tours yet';
  static const String hostNoToursBody =
      'Add a tour to describe the route, the meeting point and the price.';
  static const String hostNoBookingsTitle = 'No booking requests';
  static const String hostNoBookingsBody =
      'Requests against your experiences appear here for you to accept or '
      'decline.';
  static const String hostTitleLabel = 'Title';
  static const String hostCityLabel = 'City';
  static const String hostCategoryLabel = 'Category';
  static const String hostDescriptionLabel = 'Description';
  static const String hostPriceLabel = 'Price (USD)';
  static const String hostDurationLabel = 'Duration';
  static const String hostItineraryLabel = 'Itinerary';
  static const String hostMeetingPointLabel = 'Meeting point';
  static const String hostDifficultyLabel = 'Difficulty';
  static const String hostMaxGuestsLabel = 'Maximum guests';
  static const String hostHeroImageLabel = 'Photo URL (optional)';
  static const String hostDelete = 'Delete';
  static const String hostKeep = 'Keep';
  static const String hostDeleteExperienceTitle = 'Delete this experience?';
  static const String hostDeleteExperienceBody =
      'It disappears from your dashboard. Bookings already made are not '
      'affected.';
  static const String hostDeleteTourTitle = 'Delete this tour?';
  static const String hostDeleteTourBody =
      'It disappears from your dashboard for good.';
  static const String hostExperienceSaved = 'Experience saved';
  static const String hostTourSaved = 'Tour saved';
  static const String hostExperienceDeleted = 'Experience removed';
  static const String hostTourDeleted = 'Tour removed';
  static const String hostActive = 'Active';
  static const String hostInactive = 'Inactive';
  static const String hostAccept = 'Accept';
  static const String hostDecline = 'Decline';
  static const String hostStatExperiences = 'Experiences';
  static const String hostStatTours = 'Tours';
  static const String hostStatOpenRequests = 'Open requests';
  static const String hostStatGuests = 'Guests booked';
  static const String hostGuestLabel = 'Guest';
  static const String hostContactLabel = 'Contact';
  static const String hostNotesLabel = 'Notes';
  static const String hostRecordMissingTitle = 'No longer available';
  static const String hostRecordMissingBody =
      'This item is not in your account any more. It may have been deleted '
      'elsewhere.';
  static const String hostTitleTooShort = 'Use at least 3 characters.';
  static const String hostCityRequired = 'Add the city.';
  static const String hostCategoryRequired = 'Add a category.';
  static const String hostDescriptionTooShort =
      'Write at least 30 characters.';
  static const String hostDurationRequired =
      'Add a duration, e.g. 3 hours.';
  static const String hostPriceInvalid = 'Enter a price greater than 0.';
  static const String hostItineraryTooShort = 'Write at least 10 characters.';
  static const String hostMeetingPointRequired = 'Add a meeting point.';
  static const String hostDifficultyRequired =
      'Add a difficulty, e.g. Easy.';
  static const String hostMaxGuestsInvalid =
      'Enter between 1 and 100 guests.';

  // Sections
  static const String sectionYourActivity = 'Your activity';
  static const String sectionPlanSupport = 'Plan & support';
  static const String sectionGuideTools = 'Guide tools';
  static const String sectionHostTools = 'Host tools';
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
