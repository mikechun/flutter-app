import 'package:flutter/material.dart';

class DatePicker extends StatefulWidget {
  final ValueChanged<DateTime> onChange;
  final DateTime date;

  DatePicker({ required this.date, required this.onChange });

  @override
  State<DatePicker> createState() => _DatePickerState();
}

class _DatePickerState extends State<DatePicker> {
  late DateTime selectedDate;

  @override
  void initState() {
    super.initState();
    selectedDate = widget.date;
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );

    if (date != null && date != selectedDate) {
      setState(() {
        selectedDate = selectedDate.copyWith(year: date.year, month: date.month, day: date.day);
      });

      widget.onChange(selectedDate);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    TimeOfDay? time = await showTimePicker(
      context: context,
      initialEntryMode: TimePickerEntryMode.inputOnly,
      initialTime: TimeOfDay.fromDateTime(selectedDate),
    );

    if (time != null) {
      int minute = (time.minute / 30).round() * 30;
      int hour = time.hour;

      if (minute >= 60) {
        hour += (minute / 60).floor();
        minute = minute % 60;
      }

      setState(() {
        selectedDate = selectedDate.copyWith(hour: hour, minute: minute);
      });

      widget.onChange(selectedDate);
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
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      label: Text('${selectedDate.year}/${selectedDate.month}/${selectedDate.day}'),
                      icon: Icon(Icons.calendar_today),
                      onPressed: () { _selectDate(context); },
                    ),
                    TextButton.icon(
                      label: Text('${selectedDate.hour.toString().padLeft(2, '0')}:${selectedDate.minute.toString().padLeft(2, '0')}'),
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
