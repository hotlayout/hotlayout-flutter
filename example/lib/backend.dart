/// What this app's backend returns: values for the paths the document is
/// bound to. In a real app this map comes from your API.
const Map<String, Object?> backendData = {
  // flat: the key is the whole path
  'user.firstName': 'Alex',
  'user.points': 1250,
  'user.level': 3,
  'user.isPremium': true,
  'user.memberSince': '2025-03-14T09:00:00.000Z',

  // nested: the path is walked segment by segment
  'campaign': {'title': 'Autumn rewards', 'endsAt': '2026-11-30T23:59:59.000Z'},
  'offer': {'title': 'Weekend cashback', 'code': 'WEEKEND10', 'endsAt': '2026-10-31T23:59:59.000Z'},
  'task': {
    'title': 'Make 5 card payments',
    'description': 'Pay with your card five times this week.',
    'progress': 3,
    'target': 5,
    'completed': false,
    'rewardPoints': 100,
    'status': 'inProgress',
  },

  // a collection: a list of records under the collection name;
  // a record uses field names (`title`), not full paths (`task.title`)
  'tasks': [
    {
      'title': 'Make 5 card payments',
      'progress': 3,
      'target': 5,
      'completed': false,
      'rewardPoints': 100,
      'status': 'inProgress',
    },
    {
      'title': 'Bring a friend',
      'progress': 1,
      'target': 1,
      'completed': true,
      'completedAt': '2026-10-01T10:00:00.000Z',
      'rewardPoints': 250,
      'status': 'completed',
    },
    {
      'title': 'Top up 500',
      'progress': 0,
      'target': 1,
      'completed': false,
      'rewardPoints': 400,
      'status': 'locked',
    },
  ],
  'items': [
    {'id': 'headphones', 'name': 'Wireless headphones', 'description': 'Noise cancelling', 'price': 900},
    {'id': 'backpack', 'name': 'City backpack', 'description': '20 litres', 'price': 600},
    {'id': 'coffee', 'name': 'Coffee set', 'description': 'Two cups and a press', 'price': 350},
  ],
};
