/* eslint-disable
    camelcase,
    max-len,
    no-return-assign,
*/
// TODO: This file was created by bulk-decaffeinate.
// Fix any style issues and re-enable lint.
/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
import App from '../../../base'

export default App.controller('FileTreeRootFolderController', function(
  $scope,
  $modal,
  ide
) {
  const { rootFolder } = $scope
  return ($scope.onDrop = function(events, ui) {
    let entities
    if (ide.fileTreeManager.multiSelectedCount()) {
      entities = ide.fileTreeManager.getMultiSelectedEntityChildNodes()
    } else {
      entities = [$(ui.draggable).scope().entity]
    }

    const ids = rootFolder.children.map(entity => entity.id)

    for (let dropped_entity of Array.from(entities)) {
      if (!ids.includes(dropped_entity.id)) {
        try {
          ide.fileTreeManager.moveEntity(dropped_entity, rootFolder)
        } catch (err) {
          $modal.open({
            templateUrl: 'duplicateFileModalTemplate',
            controller: 'DuplicateFileModalController',
            resolve: {
              fileName() {
                return dropped_entity.name
              }
            }
          })
        }
      }
    }
    $scope.$digest()
    // clear highlight explicitly
    return $('.file-tree-inner .droppable-hover').removeClass('droppable-hover')
  })
})
