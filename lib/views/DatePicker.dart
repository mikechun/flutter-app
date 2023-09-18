import 'package:flutter/material.dart';

class DatePicker extends StatefulWidget {

  @override
  State<DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends State<DatePicker> {
  TimeOfDay selectedTime = TimeOfDay.now();
  DateTime selectedDate = DateTime.now();

  Future<void> _selectDate(BuildContext context) async {
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (date != null && date != selectedDate) {
      setState(() {
        selectedDate = date;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    TimeOfDay? time = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      initialTime: selectedTime,
    );

    if (time != null && time != selectedTime) {
      setState(() {
        selectedTime = time;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Center(
              child: 
                Row(
                  children: [
                    TextButton.icon(
                      label: Text('${selectedDate.year}/${selectedDate.month}/${selectedDate.day}'),
                      icon: Icon(Icons.calendar_today),
                      onPressed: () { _selectDate(context); },
                    ),
                    TextButton.icon(
                      label: Text('${selectedTime.hour}:${selectedTime.minute}'),
                      icon: Icon(Icons.access_time),
                      onPressed: () { _selectTime(context); },
                    ),
                  ],
                )
            )
          ],
        );
  }
}
