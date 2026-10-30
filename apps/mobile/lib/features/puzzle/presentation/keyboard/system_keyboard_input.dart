import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reads the phone's own keyboard through an invisible one-character text
/// field. The field always holds [_sentinel] so a backspace still arrives when
/// the word is empty; every edit is turned into characters / backspaces and
/// the field is reset. No suggestions or autocorrect: each key is one letter.
class SystemKeyboardInput extends StatefulWidget {
  const SystemKeyboardInput({
    super.key,
    required this.focusNode,
    required this.onCharacter,
    required this.onBackspace,
    required this.onSubmit,
    this.enabled = true,
  });

  final FocusNode focusNode;
  final ValueChanged<String> onCharacter;
  final VoidCallback onBackspace;

  /// The keyboard's action key (shown as "next").
  final VoidCallback onSubmit;
  final bool enabled;

  /// Opens the keyboard again after the player closed it.
  static void show(FocusNode node) {
    if (node.hasFocus) {
      SystemChannels.textInput.invokeMethod<void>('TextInput.show').ignore();
    } else {
      node.requestFocus();
    }
  }

  @override
  State<SystemKeyboardInput> createState() => _SystemKeyboardInputState();
}

class _SystemKeyboardInputState extends State<SystemKeyboardInput> {
  static const _sentinel = '​';
  static const _empty = TextEditingValue(text: _sentinel, selection: TextSelection.collapsed(offset: 1));

  final _text = TextEditingController.fromValue(_empty);

  @override
  void didUpdateWidget(covariant SystemKeyboardInput old) {
    super.didUpdateWidget(old);
    if (!widget.enabled && old.enabled) widget.focusNode.unfocus();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (value.isEmpty) {
      widget.onBackspace();
    } else {
      for (final rune in value.replaceAll(_sentinel, '').runes) {
        widget.onCharacter(String.fromCharCode(rune));
      }
    }
    _text.value = _empty;
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 1,
        height: 1,
        child: Opacity(
          opacity: 0,
          child: TextField(
            controller: _text,
            focusNode: widget.focusNode,
            autofocus: widget.enabled,
            readOnly: !widget.enabled,
            showCursor: false,
            enableInteractiveSelection: false,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            onChanged: _onChanged,
            onEditingComplete: widget.onSubmit,
            decoration: const InputDecoration.collapsed(hintText: null),
          ),
        ),
      ),
    );
  }
}
