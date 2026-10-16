/// Sample values for bindings - **a mirror of the data dictionary**
/// (`assets/contract/data-contract.json`).
///
/// Keys are flat and match the paths in documents; collection records are
/// nested, because that is how a backend response looks (the field inside a record
/// is `title`, while the binding path is `task.title`). `ScreenData` reads both
/// forms, and they sit side by side here on purpose: both must be kept working.
///
/// The values here are not cosmetic: `visibleIf` is evaluated
/// against this same map, so a mismatch with the dictionary means not "different text on
/// screen" but "block present / block absent". So the map is complete (all dictionary paths) and
/// is checked against the artifact by `sample_data_test.dart`: it cannot silently
/// drift from the dictionary.
///
/// **THE FIRST RECORD OF EACH COLLECTION DELIBERATELY DOES NOT DUPLICATE THE DICTIONARY SAMPLE**
/// of its label field. Otherwise a node inside a repeater and the same node
/// outside it would render identical text, and the record scope would look
/// broken exactly where it works.
///
/// The boundary with the COLLECTION SOURCE (`collection_source.dart`) is unchanged:
/// the screen scope supplied by the host is stronger than these values, so a catalog from the
/// network overrides a sample, not the other way round.
library;

import 'sample_images.dart';

/// The moment the samples are IMAGINED at (`x-sampleNow` of data dictionary 1.2.0).
///
/// The demo uses it as the renderer's "now": then "N days left" (`daysUntil`,
/// schema 9.4.0) on the samples gives the same number today and a year from now -
/// `campaign.endsAt` is 52 days, `offer.endsAt` is 22 - and the same as the builder
/// canvas shows. A real app has no such moment: it uses the device
/// clock. Checked against the artifact in `sample_data_test.dart`.
const String kSampleNow = '2026-10-10T09:00:00.000Z';

/// Records of the `tasks` collection - the `task` item.
const List<Map<String, Object?>> sampleTasks = [
  {
    'title': 'Spend 500 with your card',
    'id': 'task-1',
    'description': 'Any amount, any merchant',
    'image': kSampleTaskImage,
    'progress': 3,
    'target': 5,
    'completed': false,
    'completedAt': '2026-10-03T10:14:35.000Z',
    'rewardPoints': 100,
    'status': 'inProgress',
  },
  {
    'title': 'Set up a recurring payment',
    'id': 'task-2',
    'description': 'Any amount, any merchant',
    'image': kSampleTaskImage,
    'progress': 1,
    'target': 1,
    'completed': true,
    'completedAt': '2026-10-03T10:14:35.000Z',
    'rewardPoints': 50,
    'status': 'completed',
  },
  {
    'title': 'Invite a friend',
    'id': 'task-3',
    'description': 'Any amount, any merchant',
    'image': kSampleTaskImage,
    'progress': 0,
    'target': 1,
    'completed': false,
    'completedAt': '2026-10-03T10:14:35.000Z',
    'rewardPoints': 200,
    'status': 'locked',
  },
];

/// Records of the NESTED collection `taskGroup.tasks` - the same `task` item.
///
/// The same entity as in the flat list: a task inside a group has the same
/// fields as a standalone one, and a second prefix would mean describing them twice.
const List<Map<String, Object?>> sampleGroupTasks = [
  {
    'title': 'Pay a utility bill',
    'id': 'group-task-1',
    'description': 'Any amount, any merchant',
    'image': kSampleTaskImage,
    'progress': 3,
    'target': 5,
    'completed': true,
    'completedAt': '2026-10-03T10:14:35.000Z',
    'rewardPoints': 100,
    'status': 'completed',
  },
  {
    'title': 'Top up your balance',
    'id': 'group-task-2',
    'description': 'Any amount, any merchant',
    'image': kSampleTaskImage,
    'progress': 3,
    'target': 5,
    'completed': false,
    'completedAt': '2026-10-03T10:14:35.000Z',
    'rewardPoints': 100,
    'status': 'inProgress',
  },
  {
    'title': 'Order a card',
    'id': 'group-task-3',
    'description': 'Any amount, any merchant',
    'image': kSampleTaskImage,
    'progress': 3,
    'target': 5,
    'completed': false,
    'completedAt': '2026-10-03T10:14:35.000Z',
    'rewardPoints': 100,
    'status': 'locked',
  },
];

/// Records of the `doneTasks` collection - the same `task` item (dictionary 1.7.0): the tasks a person has completed.
/// A task moves here from `tasks` when it is done, and a page opened from a row of `tasks` finds its record here
/// (the live record, schema 9.27.0).
const List<Map<String, Object?>> sampleDoneTasks = [
  {
    'id': 'done-1',
    'title': 'Pay a gas bill',
    'description': 'Any amount, any merchant',
    'image': kSampleTaskImage,
    'progress': 2,
    'target': 2,
    'completed': true,
    'completedAt': '2026-10-02T08:40:00.000Z',
    'rewardPoints': 80,
    'status': 'completed',
  },
];

/// Records of the `activities` collection - the `activity` item (dictionary 1.6.0): the history, one record per
/// operation, in the order the backend sorted them (the days follow one another).
const List<Map<String, Object?>> sampleActivities = [
  {'title': 'Coffee week', 'points': 120, 'day': 'Today'},
  {'title': 'Movie night', 'points': -300, 'day': 'Today'},
  {'title': 'Strong week', 'points': 80, 'day': 'Yesterday'},
];

/// Records of the `taskGroups` collection - the `taskGroup` item.
///
/// Each group carries its OWN `tasks` array, not a reference to it: that is how
/// a backend response looks, and it is for this case that the repeater allows
/// two nesting levels.
const List<Map<String, Object?>> sampleTaskGroups = [
  {
    'title': 'Weekly streak',
    'description': 'Complete all tasks before the end of the month',
    'totalTasks': 5,
    'completedTasks': 3,
    'completed': false,
    'rewardPoints': 500,
    'tasks': sampleGroupTasks,
  },
  {
    'title': 'Summer marathon',
    'description': 'Complete all tasks before the end of the month',
    'totalTasks': 4,
    'completedTasks': 4,
    'completed': true,
    'rewardPoints': 500,
    'tasks': sampleGroupTasks,
  },
];

/// Records of the `items` collection - the `item` item.
///
/// `selectedId` is not arbitrary here: these are the identifiers the
/// `reward-catalog-screens` fixture rows use for their options (`optionValue`).
/// A gap between them would mean that picking by finger leads to details that do not exist.
///
/// The record NAMES deliberately do NOT match those options' labels: on the catalog
/// screen the data list sits under the choice group, and identical labels
/// would mean neither a test nor a person could tell a list row from an option.
const List<Map<String, Object?>> sampleItems = [
  {
    'name': 'Bluetooth speaker',
    'image': kSampleHeadphonesImage,
    'description': 'Noise cancelling, 30h battery',
    'price': 2400,
    'selectedId': 'speaker',
  },
  {
    'name': 'Canvas backpack',
    'image': kSampleBackpackImage,
    'description': 'Fits a 15-inch laptop',
    'price': 3200,
    'selectedId': 'backpack',
  },
  {
    'name': 'Coffee grinder set',
    'image': kSampleCoffeeSetImage,
    'description': 'Two cups and a grinder',
    'price': 1500,
    'selectedId': 'coffee-set',
  },
];

/// Records of the `offers` collection - the `offer` item.
const List<Map<String, Object?>> sampleOffers = [
  {
    'title': 'Cashback week',
    'description': 'Pay with your card on Saturday and Sunday',
    'image': kSampleOfferImage,
    'endsAt': '2026-10-31T23:59:59.000Z',
    'discountPercent': 10,
    'price': 80,
    'isActive': true,
    'code': 'WEEKEND20',
  },
  {
    'title': 'Free delivery in October',
    'description': 'Pay with your card on Saturday and Sunday',
    'image': kSampleOfferImage,
    'endsAt': '2026-10-31T23:59:59.000Z',
    'discountPercent': 0,
    'price': 45.5,
    'isActive': true,
    'code': 'OCTSHIP',
  },
];

/// The whole data dictionary as values: its paths plus seven collections.
const Map<String, Object?> sampleScreenData = {
  // ----------------------------------------------------------------- user.*
  'user.firstName': 'Alex',
  'user.points': 1250,
  'user.level': 3,
  'user.isPremium': false,
  'user.memberSince': '2026-01-15T12:00:00.000Z',

  // ---------------------------------------------------------------- offer.*
  'offer.title': 'Double points this weekend',
  'offer.description': 'Pay with your card on Saturday and Sunday',
  'offer.image': kSampleOfferImage,
  'offer.endsAt': '2026-10-31T12:00:00.000Z',
  'offer.discountPercent': 20,
  // Dictionary 1.2.0: an amount shown with the `currency` format ("120 JOD").
  'offer.price': 120,
  'offer.isActive': true,
  'offer.code': 'WEEKEND20',

  // ----------------------------------------------------------------- task.*
  //
  // `completed: false`, not `true`: on the progress screen the "still in progress"
  // block depends on this flag. The values here are not cosmetic: they decide
  // which nodes are on screen at all.
  'task.title': 'Make 5 card payments',
  'task.description': 'Any amount, any merchant',
  'task.image': kSampleTaskImage,
  'task.progress': 3,
  'task.target': 5,
  'task.completed': false,
  'task.completedAt': '2026-10-03T10:14:35.000Z',
  'task.rewardPoints': 100,
  'task.status': 'inProgress',

  // ------------------------------------------------------------ taskGroup.*
  'taskGroup.title': 'October challenge',
  'taskGroup.description': 'Complete all tasks before the end of the month',
  'taskGroup.totalTasks': 5,
  'taskGroup.completedTasks': 3,
  'taskGroup.completed': false,
  'taskGroup.rewardPoints': 500,

  // ----------------------------------------------------------------- item.*
  //
  // `item.selectedId` is not just a sample but the START MARK: the choice
  // group writes into it (8.1.0), and the details screen finds the record by it. So
  // the value must be an id that really exists in the catalog.
  'item.name': 'Wireless headphones',
  'item.image': kSampleHeadphonesImage,
  'item.description': 'Noise cancelling, 30h battery',
  'item.price': 4900,
  'item.selectedId': 'headphones',

  // ------------------------------------------------------------- campaign.*
  'campaign.title': 'Autumn rewards',
  'campaign.endsAt': '2026-11-30T12:00:00.000Z',

  // ------------------------------------------------- form.*, settings.* (1.3.0)
  //
  // Paths the screen WRITES (input fields 9.13.0): the values here are what the screen
  // opens with until the user types anything. `form.phoneError` is the error
  // text, which the HOST supplies as data; the reader validates nothing itself.
  'form.fullName': 'Alex Morgan',
  'form.email': 'alex@example.com',
  'form.phone': '0790 000',
  'form.phoneError': 'Enter the number with the country code',
  'form.comment': 'Call me after six',
  'form.agreed': false,
  'settings.notifications': true,
  'settings.marketing': false,

  // --------------------------------------------------------- survey.* (1.4.0)
  //
  // Survey paths (form 9.14.0). On the sample data the form is FILLED, so the
  // "Next" buttons are enabled; an empty form comes from a screen without host data.
  // `survey.age` is a number (numeric field).
  'survey.goal': 'rewards',
  'survey.name': 'Alex',
  'survey.age': 34,
  'survey.comment': 'More rewards for books, please',
  'survey.agreed': false,
  // Dictionary 1.5.0: a score and the topics of a choice-controls survey.
  'survey.score': 8,
  'survey.topicTravel': true,
  'survey.topicFood': false,
  'survey.topicBooks': false,

  // --------------------------------------------------------- account.* (1.5.0)
  //
  // An account for the money screens (schema 9.19.0): amounts with a fraction part and a negative
  // one, the last operation, and two state paths (hidden balance, shown period). Numbers are numbers:
  // a `currency` binding formats them and a `sign` binding writes the sign.
  'account.balance': 24580.75,
  'account.income': 42000,
  'account.spent': -1200.5,
  'account.limit': 500,
  'account.lastIcon': 'trending-up',
  'account.lastStatus': 'Credited',
  'account.lastMerchant': 'Corner bakery',
  'account.lastAt': '2026-10-15T09:30:00.000Z',
  'account.balanceHidden': false,
  'account.period': 'week',

  // Dictionary 1.6.0 and 1.7.0: the history record and the id of a task.
  'activity.title': 'Welcome bonus',
  'activity.points': 50,
  'activity.day': 'Mon, Oct 12',
  'task.id': 'card-payments',

  // --------------------------------------------------------------- collections
  'tasks': sampleTasks,
  'doneTasks': sampleDoneTasks,
  'activities': sampleActivities,
  'taskGroups': sampleTaskGroups,
  'items': sampleItems,
  'offers': sampleOffers,
};
