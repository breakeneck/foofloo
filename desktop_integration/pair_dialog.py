"""Drop-in pairing dialog for the desktop FooQt client.

foobar-qt is the user's git territory (no commits from the agent), so this
lives here as a ready-to-paste snippet. Attach it to a menu item:

    action = menu.addAction("Pair device")
    action.triggered.connect(lambda: PairDialog(window).exec())

Uses the existing RemoteClient (remote.py): its master token authorizes
POST /pair on the agent (agent >= 1.4.0).
"""

from PyQt6 import QtCore, QtWidgets


class PairDialog(QtWidgets.QDialog):
    def __init__(self, parent, remote_client):
        """remote_client: the app's shared RemoteClient instance."""
        super().__init__(parent)
        self.setWindowTitle("Pair a device")
        self._client = remote_client
        layout = QtWidgets.QVBoxLayout(self)
        self._name = QtWidgets.QLineEdit("android phone")
        layout.addWidget(QtWidgets.QLabel("Device name:"))
        layout.addWidget(self._name)
        self._code = QtWidgets.QLabel("-")
        font = self._code.font()
        font.setPointSize(28)
        font.setBold(True)
        self._code.setFont(font)
        self._code.setAlignment(QtCore.Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(self._code)
        self._timer = QtCore.QTimer(self, singleShot=True)
        self._timer.timeout.connect(lambda: self._code.setText("expired"))
        btn = QtWidgets.QPushButton("Generate code")
        btn.clicked.connect(self._generate)
        layout.addWidget(btn)
        layout.addWidget(QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.StandardButton.Close,
            accepted=self.accept))

    def _generate(self):
        try:
            port = self._client.ensure_agent()
            resp = self._client.request(
                "POST", "/pair", {"name": self._name.text()})
        except Exception as e:
            self._code.setText("error: %s" % e)
            return
        self._code.setText(resp["code"])
        self._timer.start(resp.get("expires_in", 60) * 1000)