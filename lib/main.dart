import 'package:flutter/material.dart';

void main() {
  runApp(FuelAverageApp());
}

class FuelAverageApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fuel Average Calculator',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: FuelAverageCalculator(),
    );
  }
}

class FuelAverageCalculator extends StatefulWidget {
  @override
  _FuelAverageCalculatorState createState() => _FuelAverageCalculatorState();
}

class _FuelAverageCalculatorState extends State<FuelAverageCalculator> {
  final _distanceController = TextEditingController();
  final _fuelController = TextEditingController();
  String _result = '';

  void _calculateFuelAverage() {
    final double? distance = double.tryParse(_distanceController.text);
    final double? fuel = double.tryParse(_fuelController.text);

    if (distance != null && fuel != null && fuel > 0) {
      final fuelAverage = distance / fuel;
      setState(() {
        _result = 'Fuel Average: ${fuelAverage.toStringAsFixed(2)} km/l';
      });
    } else {
      setState(() {
        _result = 'Please enter valid numbers for distance and fuel.';
      });
    }
  }

  void _resetFields() {
    _distanceController.clear();
    _fuelController.clear();
    setState(() {
      _result = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fuel Average Calculator'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _distanceController,
              decoration: InputDecoration(
                labelText: 'Distance traveled (km)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            TextField(
              controller: _fuelController,
              decoration: InputDecoration(
                labelText: 'Fuel used (liters)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _calculateFuelAverage,
              child: Text('Calculate'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _resetFields,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: Text('Reset'),
            ),
            SizedBox(height: 20),
            Text(
              _result,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
