/// Built-in word categories for Imposter. Each category gets a list of
/// secret words that all townspeople see; the imposter sees only the
/// category name.
const Map<String, List<String>> imposterCategories = {
  'Food': [
    'pizza', 'sushi', 'taco', 'burger', 'ramen', 'cake', 'ice cream',
    'pasta', 'pancake', 'sandwich', 'curry', 'salad', 'soup', 'bagel',
    'doughnut', 'fries', 'omelette', 'lasagna', 'kebab', 'risotto',
  ],
  'Animal': [
    'dog', 'cat', 'elephant', 'dolphin', 'eagle', 'snake', 'panda',
    'lion', 'tiger', 'rabbit', 'shark', 'octopus', 'penguin', 'horse',
    'kangaroo', 'sloth', 'owl', 'wolf', 'fox', 'bear',
  ],
  'Place': [
    'beach', 'forest', 'desert', 'mountain', 'city', 'farm', 'school',
    'hospital', 'airport', 'library', 'museum', 'theater', 'park',
    'subway', 'castle', 'casino', 'restaurant', 'gym', 'church', 'bridge',
  ],
  'Movie': [
    'Star Wars', 'Titanic', 'Inception', 'Avatar', 'The Matrix', 'Frozen',
    'Avengers', 'Toy Story', 'Jaws', 'Up', 'Coco', 'Shrek', 'Rocky',
    'Gladiator', 'Interstellar', 'Pulp Fiction', 'The Godfather', 'Joker',
    'La La Land', 'Parasite',
  ],
  'Sport': [
    'soccer', 'basketball', 'tennis', 'baseball', 'hockey', 'cricket',
    'golf', 'rugby', 'volleyball', 'swimming', 'cycling', 'boxing',
    'fencing', 'archery', 'skiing', 'surfing', 'climbing', 'judo',
    'rowing', 'badminton',
  ],
};
