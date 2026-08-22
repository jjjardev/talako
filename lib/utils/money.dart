double roundMoney(double amount) => (amount * 100).roundToDouble() / 100;

bool moneyEquals(double a, double b) => (a - b).abs() < 0.01;

bool isFullPayment(double paid, double total) => moneyEquals(paid, total);

double clampMoney(double value, double min, double max) =>
    roundMoney(value.clamp(min, max).toDouble());
