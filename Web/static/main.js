document.addEventListener("DOMContentLoaded", () => {
    const firstInput = document.querySelector("input[autofocus], form input");

    if (firstInput) {
        firstInput.focus();
    }
});
