import 'package:flutter/material.dart';


class SOSButton extends StatefulWidget {
const SOSButton({super.key});


@override
State<SOSButton> createState() => _SOSButtonState();
}


class _SOSButtonState extends State<SOSButton> with SingleTickerProviderStateMixin {
late final AnimationController _ctrl = AnimationController(
vsync: this,
duration: const Duration(seconds: 2),
)..repeat(reverse: true);


@override
void dispose() {
_ctrl.dispose();
super.dispose();
}


void _onPressed() {
// TODO: Wire up SOS logic (send location, notify contacts/authorities, etc.)
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text('SOS Triggered (demo)')),
);
}


@override
Widget build(BuildContext context) {
return AnimatedBuilder(
animation: _ctrl,
builder: (context, child) {
final scale = 1.0 + (_ctrl.value * 0.08);
final shadow = 10.0 + (_ctrl.value * 20.0);
return Transform.scale(
scale: scale,
child: ElevatedButton(
style: ElevatedButton.styleFrom(
padding: const EdgeInsets.all(40),
shape: const CircleBorder(),
elevation: shadow,
backgroundColor: Colors.red,
foregroundColor: Colors.white,
),
onPressed: _onPressed,
child: const Text('S.O.S', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
),
);
},
);
}
}