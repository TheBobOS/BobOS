import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#0d0e22"

            Image {
                id: logo
                source: "bobos-logo.svg"
                width: 420
                height: 420
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -40
            }

            Text {
                text: "Installation de BobOS"
                color: "#00ffcc"
                font.pixelSize: 28
                font.bold: true
                anchors.top: logo.bottom
                anchors.topMargin: 24
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Text {
                text: "100% hors-ligne — BobOS Team"
                color: "#888899"
                font.pixelSize: 16
                anchors.top: parent.verticalCenter
                anchors.topMargin: 250
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    function onActivate() {
        presentation.currentSlide = 0;
    }
}
