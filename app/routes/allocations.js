const AllocationsDAO = require("../data/allocations-dao").AllocationsDAO;
const {
    environmentalScripts
} = require("../../config/config");

function AllocationsHandler(db) {
    "use strict";

    const allocationsDAO = new AllocationsDAO(db);

    this.displayAllocations = (req, res, next) => {
       
                // Use the logged-in user's identity and reject other users' URLs.
        const { userId } = req.session;

        if (userId === undefined || userId === null) {
            return res.redirect("/login");
        }

        if (req.params.userId !== String(userId)) {
            return res.status(403).send("Access denied");
            }   
        const {
            threshold
        } = req.query;

        allocationsDAO.getByUserIdAndThreshold(userId, threshold, (err, allocations) => {
            if (err) {
    if (err.code === "INVALID_THRESHOLD") {
        return res.status(400).send(err.message);
    }

    return next(err);
}
            return res.render("allocations", {
                userId,
                allocations,
                environmentalScripts
            });
        });
    };
}

module.exports = AllocationsHandler;
